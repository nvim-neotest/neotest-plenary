_G._run_tests = function(args)
  local success = pcall(function()
    local filters = args.filter or {}
    local file = args.file
    local results
    local code = 0

    local busted = require("plenary.busted")
    local async = require("neotest.async")
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

    local function add_to_locations(desc, func)
      local info = debug.getinfo(func, "S")
      func_locations[desc] = vim.list_extend(func_locations[desc] or {}, { info.linedefined - 1 })
    end

    local final_filter = filters[#filters]

    local function filter(func)
      if #filters > 0 or final_filter then
        local filter_start, filter_end = unpack(filters[1] or final_filter)
        local func_info = debug.getinfo(func, "S")
        local func_start, func_end = func_info.linedefined - 1, func_info.lastlinedefined - 1
        if filter_start > func_start or filter_end < func_end then
          return false
        end
        if #filters > 0 then
          table.remove(filters, 1)
        end
      end
      return true
    end

    local function wrap_busted_func(busted_func, is_async)
      return function(desc, func)
        if not filter(func) then
          return
        end
        add_to_locations(desc, func)
        return busted_func(desc, is_async and async.util.will_block(func) or func)
      end
    end

    async.tests.it = wrap_busted_func(busted.it, true)
    busted.describe = wrap_busted_func(busted.describe)
    busted.inner_describe = wrap_busted_func(busted.inner_describe)
    busted.it = wrap_busted_func(busted.it)

    it = busted.it
    describe = busted.describe

    require("plenary.busted").run(file)
    local results_file = assert(io.open(args.results, "w"))
    results_file:write(vim.json.encode({ results = results, locations = func_locations }))
    results_file:close()
    os.exit(code)
  end)
  if not success then
    os.exit(1)
  end
end
