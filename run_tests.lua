-- The test script to run busted tests in a separate headless nvim process

local colored = function(color, str)
  local color_table = {
    red = 31,
    green = 32,
    yellow = 33,
  }
  return string.format(
    "%s[%sm%s%s[%sm", string.char(27), color_table[color] or 0,
    str, string.char(27), 0)
end

_G._run_tests = function(args)
  local filters = args.filter or {}
  local file = args.file

  xpcall(function()
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

    ---@diagnostic disable-next-line: lowercase-global
    it = busted.it
    describe = busted.describe
    ---@diagnostic enable-next-line: lowercase-global

    busted.run(file)
    local results_file = assert(io.open(args.results, "w"))
    results_file:write(vim.json.encode({ results = results, locations = func_locations }))
    results_file:close()

    os.exit(code)

  end, function(err)
    -- Show stacktrace when lua exception is thrown
    local trace = debug.traceback(err, 2)
    local msg = "\n" .. colored("red", "Error happened while testing " .. file .. ":\n")
    io.stdout:write(msg .. trace)
    io.stdout:write "\r\n"

    -- Show some debugging information in the test output
    -- this helps to troubleshoot for lua module paths
    local SEPARATOR = string.rep("=", 40)
    print("\n" .. SEPARATOR .. "\n")

    io.stdout:write(colored('yellow', "&runtimepath: ") .. vim.o.runtimepath)
    io.stdout:write "\r\n"

    os.exit(1)
  end)
end
