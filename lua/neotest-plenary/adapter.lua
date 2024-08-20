local nio = require("nio")
local lib = require("neotest.lib")
local base = require("neotest-plenary.base")
local collect_results = require("neotest-plenary.results")

---@param config { min_init?: string }
return function(config)
  ---@async
  ---@return neotest.Tree | nil
  local function discover_positions(path)
    return lib.treesitter.parse_positions(path, base.treesitter_query, { nested_namespaces = true })
  end

  local script_path = base.get_script_path()

  ---@type neotest.Adapter
  local PlenaryNeotestAdapter = {
    name = "neotest-plenary",
    root = lib.files.match_root_pattern("lua"),
    is_test_file = base.is_test_file,
    discover_positions = discover_positions,
    ---@param args neotest.RunArgs
    ---@return neotest.RunSpec | nil
    build_spec = function(args)
      local results_path = nio.fn.tempname()
      local tree = args.tree
      if not tree then
        return
      end
      local pos = args.tree:data()
      if pos.type == "dir" then
        return
      end
      local filters = {}
      if pos.type == "namespace" or pos.type == "test" then
        table.insert(filters, 1, pos.range[1])
        for parent in tree:iter_parents() do
          local parent_pos = parent:data()
          if parent_pos.type ~= "namespace" then
            break
          end
          table.insert(filters, 1, parent_pos.range[1])
        end
      end
      local min_init = config.min_init
      if not min_init then
        local globs = {
          ("**%stestrc*"):format(lib.files.sep),
          ("**%sminimal_init*"):format(lib.files.sep),
          ("test*%sinit.vim"):format(lib.files.sep),
        }
        for _, pattern in ipairs(globs) do
          local glob_matches = nio.fn.glob(pattern, true, true)
          if #glob_matches > 0 then
            min_init = glob_matches[1]
            break
          end
        end
      end

      -- the local path to the plenary.nvim plugin installed
      ---@type string
      local plenary_dir = vim.fn.fnamemodify(
        debug.getinfo(require("plenary.path").__index).source:match("@?(.*[/\\])"),
        ":p:h:h:h"
      )

      local command = vim
        .iter({
          vim.loop.exepath(),
          "--headless",
          "-i",
          "NONE", -- no shada
          "-n", -- no swapfile, always in-memory
          "--noplugin",
          -- add plenary.nvim to &runtimepath (should be available before init config)
          "--cmd",
          ([[lua vim.opt.runtimepath:prepend('%s')]]):format(vim.fn.escape(plenary_dir, " '")),
          -- Make lua modules at ./lua/ loadable
          "--cmd",
          [[lua package.path = 'lua/?.lua;' .. 'lua/?/init.lua;' .. package.path]],
          "-u",
          min_init or "NONE",
          "-c",
          "source " .. script_path,
          "-c",
          "lua _run_tests({results = '" .. results_path .. "', file = '" .. nio.fn.escape(
            pos.path,
            "'"
          ) .. "', filter = " .. vim.inspect(filters) .. "})",
        })
        :flatten()
        :totable()
      return {
        command = command,
        context = {
          results_path = results_path,
          file = pos.path,
        },
      }
    end,
    ---@async
    ---@param spec neotest.RunSpec
    ---@param _ neotest.StrategyResult
    ---@param tree neotest.Tree
    ---@return neotest.Result[]
    results = function(spec, _, tree)
      if tree:data().type == "file" and #tree:children() == 0 then
        tree = discover_positions(tree:data().path)
      end
      return collect_results(spec, tree)
    end,
  }

  return PlenaryNeotestAdapter
end
