local async = require("neotest.async")
local Path = require("plenary.path")
local lib = require("neotest.lib")
local base = require("neotest-plenary.base")

-- the local path to the plenary.nvim plugin installed
---@type string
local plenary_dir = vim.fn.fnamemodify(
  debug.getinfo(require("plenary.busted").run).source:match("@?(.*[/\\])"), ":p:h:h:h"
)

local config = {
  min_init = nil,
}

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match(("(.*%s)"):format(lib.files.sep))
end

local function join_results(base_result, update)
  if not base_result or not update then
    return base_result or update
  end
  local status = (base_result.status == "failed" or update.status == "failed") and "failed"
    or "passed"
  local errors = (base_result.errors or update.errors)
      and (vim.list_extend(base_result.errors or {}, update.errors or {}))
    or nil
  return {
    status = status,
    errors = errors,
  }
end

-- see ../../run_tests.lua
local test_script = (Path.new(script_path()):parent():parent() / "run_tests.lua").filename

---@type neotest.Adapter
local PlenaryNeotestAdapter = { name = "neotest-plenary" }

PlenaryNeotestAdapter.root = lib.files.match_root_pattern("lua")

function PlenaryNeotestAdapter.is_test_file(file_path)
  return base.is_test_file(file_path)
end

---@async
---@return neotest.Tree | nil
function PlenaryNeotestAdapter.discover_positions(path)
  local query = [[
  ;; describe blocks
  ((function_call
      name: (identifier) @func_name (#match? @func_name "^describe$")
      arguments: (arguments (_) @namespace.name (function_definition))
  )) @namespace.definition


  ;; it blocks
  ((function_call
      name: (identifier) @func_name
      arguments: (arguments (_) @test.name (function_definition))
  ) (#match? @func_name "^it$")) @test.definition

  ;; async it blocks (async.it)
  ((function_call
      name: (
        dot_index_expression 
          field: (identifier) @func_name
      )
      arguments: (arguments (_) @test.name (function_definition))
    ) (#match? @func_name "^it$")) @test.definition
    ]]
  return lib.treesitter.parse_positions(path, query, { nested_namespaces = true })
end

---@param args neotest.RunArgs
---@return neotest.RunSpec | nil
function PlenaryNeotestAdapter.build_spec(args)
  local results_path = async.fn.tempname()
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
      local glob_matches = async.fn.glob(pattern, true, true)
      if #glob_matches > 0 then
        min_init = glob_matches[1]
        break
      end
    end
  end

  local cwd = assert(vim.loop.cwd())
  local command = vim.tbl_flatten({
    vim.loop.exepath(),
    "--headless",
    "-i", "NONE", -- no shada
    "-n", -- no swpafile, always in-memory
    "--noplugin",
    -- add plenary.nvim to &runtimepath (should be available before init config)
    "--cmd", ([[lua vim.opt.runtimepath:prepend('%s')]]):format(vim.fn.escape(plenary_dir, " '")),
    -- Make lua modules at ./lua/ loadable
    "--cmd", [[lua package.path = 'lua/?.lua;' .. 'lua/?/init.lua;' .. package.path]],
    "-u", min_init or "NONE",
    "-c", "source " .. test_script,
    "-c", "lua _run_tests({results = '" .. results_path .. "', file = '" .. async.fn.escape(
      pos.path,
      "'"
    ) .. "', filter = " .. vim.inspect(filters) .. "})",
  })
  return {
    command = command,
    context = {
      results_path = results_path,
      file = pos.path,
    },
  }
end

---@param result PlenaryTestResult
local function convert_plenary_result(result, status, file)
  return table.concat(vim.tbl_flatten({ file, result.descriptions }), "::"),
    {
      status = status,
      short = result.msg,
      errors = result.msg and {
        {
          message = result.msg,
        },
      },
    }
end

---@param lists string[][]
local function permutations(lists, cur_i)
  cur_i = cur_i or 1
  if cur_i > #lists then
    return { {} }
  end
  local sub_results = permutations(lists, cur_i + 1)
  local result = {}
  for _, elem in pairs(lists[cur_i]) do
    for _, sub_result in pairs(sub_results) do
      local l = vim.list_extend({ elem }, sub_result)
      table.insert(result, l)
    end
  end
  return result
end

---@class PlenaryTestResult
---@field descriptions string[]
---@field msg? string

---@class PlenaryTestResults
---@field pass PlenaryTestResult[]
---@field fail PlenaryTestResult[]
---@field errs PlenaryTestResult[]
---@field fatal PlenaryTestResult[]

---@class PlenaryOutput
---@field results PlenaryTestResults
---@field locations table<string, integer>

---@async
---@param spec neotest.RunSpec
---@param _ neotest.StrategyResult
---@param tree neotest.Tree
---@return neotest.Result[]
function PlenaryNeotestAdapter.results(spec, _, tree)
  if tree:data().type == "file" and #tree:children() == 0 then
    tree = PlenaryNeotestAdapter.discover_positions(tree:data().path)
  end
  -- TODO: Find out if this JSON option is supported in future
  local success, data = pcall(lib.files.read, spec.context.results_path)
  if not success then
    data = vim.json.encode({ pass = {}, fail = {}, errs = {}, fatal = {} })
  end
  ---@type PlenaryOutput
  local plenary_output = vim.json.decode(data, { luanil = { object = true } })
  if not plenary_output.results then
    return {}
  end

  local plenary_results = plenary_output.results
  local locations = plenary_output.locations
  local results = {}
  for _, plen_result in pairs(plenary_results.pass) do
    local pos_id, pos_result = convert_plenary_result(plen_result, "passed", spec.context.file)
    results[pos_id] = pos_result
  end
  local file_result = { status = "passed", errors = {} }
  local failed = vim.list_extend({}, plenary_results.errs)
  vim.list_extend(failed, plenary_results.fail)

  for _, plen_result in pairs(failed) do
    local pos_id, pos_result = convert_plenary_result(plen_result, "failed", spec.context.file)
    results[pos_id] = pos_result
    file_result.status = "failed"
    vim.list_extend(file_result.errors, pos_result.errors)
  end

  results[spec.context.file] = file_result

  --- We now have all results mapped by their runtime names
  --- Need to combine using alias map

  local aliases = {}
  local file_tree = tree
  if file_tree:data().type ~= "file" then
    for parent in tree:iter_parents() do
      if parent:data().type == "file" then
        file_tree = parent
        break
      end
    end
  end
  for alias, lines in pairs(locations) do
    for _, line in pairs(lines) do
      local node = lib.positions.nearest(file_tree, line)
      local pos = node:data()
      aliases[pos.id] = aliases[pos.id] or {}
      table.insert(aliases[pos.id], alias)
    end
  end

  local function get_result_of_node(node)
    local pos = node:data()
    if not results[pos.id] then
      local namespace_aliases = {}
      for parent in node:iter_parents() do
        if parent:data().type ~= "namespace" then
          break
        end
        table.insert(namespace_aliases, 1, aliases[parent:data().id])
      end
      local namespace_permutations = permutations(namespace_aliases)
      for _, perm in ipairs(namespace_permutations) do
        for _, alias in ipairs(aliases[pos.id] or {}) do
          local alias_id = table.concat(vim.tbl_flatten({ pos.path, perm, alias }), "::")
          results[pos.id] = join_results(results[pos.id], results[alias_id])
          results[alias_id] = nil
        end
      end
    end
    if not results[pos.id] then
      results[pos.id] = results[pos.path]
    end
  end

  for _, node in tree:iter_nodes() do
    if node:data().type == "test" then
      get_result_of_node(node)
    end
  end

  return results
end

setmetatable(PlenaryNeotestAdapter, {
  __call = function()
    return PlenaryNeotestAdapter
  end,
})

PlenaryNeotestAdapter.setup = function(opts)
  opts = opts or {}
  config.min_init = opts.min_init
  return PlenaryNeotestAdapter
end

return PlenaryNeotestAdapter
