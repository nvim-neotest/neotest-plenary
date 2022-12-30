_G._run_tests = function(args)
  local success, error = pcall(function()
    local filters = args.filter or {}
    local file = args.file
    local results
    local code = 0

    local cur_line_in_test_file = function(depth)
      depth = depth or 2
      while true do
        local func_info = debug.getinfo(depth)
        -- We've reached the end of the stack
        if not func_info then
          return nil
        end

        if func_info.source == "@" .. file then
          return func_info.currentline - 1
        end

        -- Let's try next one up
        depth = depth + 1
      end
    end

    local busted = require("plenary.busted")
    -- May be optional
    pcall(vim.cmd, "packadd neotest")
    local base_format = busted.format_results
    local func_locations = {}
    local base_cmd = vim.cmd
    vim.cmd = function(cmd)
      if vim.endswith(cmd, "cq") then
        code = string.sub(cmd, 0, 1)
        return
      end
      return base_cmd(cmd)
    end
    busted.format_results = function(results_)
      results = results_
      return base_format(results)
    end

    local final_filter = filters[#filters]

    local function should_run()
      if #filters == 0 and not final_filter then
        return true
      end

      local filter_start = filters[1] or final_filter

      local depth = 2
      local cur_line = cur_line_in_test_file(depth)
      while cur_line do
        if filter_start == cur_line then
          if #filters > 0 then
            table.remove(filters, 1)
          end
          return true
        end
        depth = depth + 1
        cur_line = cur_line_in_test_file(depth)
      end
    end

    local function wrap_busted_func(busted_func)
      return function(desc, func)
        if not should_run() then
          return
        end
        func_locations[desc] =
        vim.list_extend(func_locations[desc] or {}, { cur_line_in_test_file() })
        return busted_func(desc, func)
      end
    end

    busted.describe = wrap_busted_func(busted.describe)
    busted.inner_describe = wrap_busted_func(busted.inner_describe)
    busted.it = wrap_busted_func(busted.it)

    it = busted.it
    describe = busted.describe

    busted.run(file)
    local results_file = assert(io.open(args.results, "w"))
    results_file:write(vim.json.encode({ results = results, locations = func_locations }))
    results_file:close()
    os.exit(code)
  end)
  if not success then
    print(error)
    os.exit(1)
  end
end
