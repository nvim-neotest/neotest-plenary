_G._run_tests = function(args)
  local base_exit = os.exit
  local success = pcall(function()
    local filters = args.filter or {}
    local file = args.file
    local results
    local code

    local busted = require("plenary.busted")
    local base_format = busted.format_results
    local base_it = busted.it
    local base_describe = busted.describe
    local base_inner_describe = busted.inner_describe
    local func_locations = {}
    os.exit = function(code_)
      code = code_
    end
    busted.format_results = function(results_)
      results = results_
      return base_format(results)
    end

    local function add_to_locations(desc, func)
      local info = debug.getinfo(func, "S")
      func_locations[desc] = info.linedefined - 1
    end

    local function filter(func)
      if #filters > 0 then
        local filter_start, filter_end = unpack(filters[1])
        local func_info = debug.getinfo(func, "S")
        local func_start, func_end = func_info.linedefined - 1, func_info.lastlinedefined - 1
        if filter_start > func_start or filter_end < func_end then
          return false
        end
        table.remove(filters, 1)
      end
      return true
    end

    busted.describe = function(desc, func)
      if not filter(func) then
        return
      end
      add_to_locations(desc, func)

      return base_describe(desc, func)
    end
    busted.inner_describe = function(desc, func)
      if not filter(func) then
        return
      end
      add_to_locations(desc, func)

      return base_inner_describe(desc, func)
    end
    busted.it = function(desc, func)
      if not filter(func) then
        return
      end
      add_to_locations(desc, func)

      return base_it(desc, func)
    end

    it = busted.it
    describe = busted.describe

    require("plenary.busted").run(file)
    local results_file = assert(io.open(args.results, "w"))
    results_file:write(vim.json.encode({ results = results, locations = func_locations }))
    results_file:close()
    base_exit(code)
  end)
  base_exit(1)
end
