_G._run_tests = function(args)
  local filter = args.filter or {}
  local file = args.file
  local results
  local code

  local busted = require("plenary.busted")
  local base_format = busted.format_results
  local base_it = busted.it
  local base_describe = busted.describe
  local base_inner_describe = busted.inner_describe
  local base_exit = os.exit
  os.exit = function(code_)
    code = code_
  end
  busted.format_results = function(results_)
    results = results_
    return base_format(results)
  end
  busted.describe = function(desc, ...)
    if #filter > 0 then
      if filter[1] ~= desc then
        return
      end
      table.remove(filter, 1)
    end

    return base_describe(desc, ...)
  end
  busted.inner_describe = function(desc, ...)
    if #filter > 0 then
      if filter[1] ~= desc then
        return
      end
      table.remove(filter, 1)
    end

    return base_inner_describe(desc, ...)
  end
  busted.it = function(desc, ...)
    if #filter > 0 then
      if filter[1] ~= desc then
        return
      end
      -- If a test passes the final filter we don't want other tests running
      if #filter == 1 then
        filter = { 0 }
      else
        table.remove(filter, 1)
      end
    end

    return base_it(desc, ...)
  end

  vim.cmd("runtime plugin/plenary.vim")
  require("plenary.busted").run(file)
  local results_file = io.open(args.results, "w")
  results_file:write(vim.json.encode(results))
  results_file:close()
  base_exit(code)
end
