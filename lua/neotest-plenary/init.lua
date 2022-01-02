local logger = require("neotest.logging")
local Path = require("plenary.path")
local lib = require("neotest.lib")
local base = require("neotest-plenary.base")

local function script_path()
  local str = debug.getinfo(2, "S").source:sub(2)
  return str:match("(.*/)")
end

local test_script = (Path.new(script_path()):parent():parent() / "run_tests.sh").filename

---@type NeotestAdapter
local PlenaryNeotestAdapter = { name = "neotest-plenary" }

function PlenaryNeotestAdapter.is_test_file(file_path)
  return base.is_test_file(file_path)
end

---@async
---@return Tree | nil
function PlenaryNeotestAdapter.discover_positions(path)
  if path and not lib.files.is_dir(path) then
    local query = [[
      ((function_call
        (identifier) @func_name
        (arguments (string) @namespace.name )
      ) (#match? @func_name "describe")) @namespace.definition

      ((function_call
        (identifier) @func_name
        (arguments (string) @test.name )
      ) (#match? @func_name "it")) @test.definition
    ]]
    return lib.treesitter.parse_positions(
      path,
      query,
      { quoted_names = true, nested_namespaces = true }
    )
  end
  local files = lib.func_util.filter_list(base.is_test_file, lib.files.find({ path }))
  return lib.files.parse_dir_from_files(path, files)
end

---@param args NeotestRunArgs
---@return NeotestRunSpec | nil
function PlenaryNeotestAdapter.build_spec(args)
  local results_path = vim.fn.tempname()
  local pos = args.position
  if not pos or pos.type == "dir" then
    return
  end
  local filters = {}
  if pos.type == "namespace" or pos.type == "test" then
    table.insert(filters, 1, pos.name)
    for i = #pos.namespaces, 1, -1 do
      table.insert(filters, 1, pos.namespaces[i])
    end
  end
  local script_args = vim.tbl_flatten({
    results_path,
    pos.path,
    vim.inspect(filters),
  })
  local command = vim.tbl_flatten({
    test_script,
    script_args,
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
      errors = result.msg and { { message = result.msg } },
    }
end

---@class PlenaryTestResult
---@field descriptions string[]
---@field msg? string

---@class PlenaryTestResults
---@field pass PlenaryTestResult[]
---@field fail PlenaryTestResult[]
---@field errs PlenaryTestResult[]
---@field fatal PlenaryTestResult[]

---@async
---@param spec NeotestRunSpec
---@param result NeotestStrategyResult
---@return NeotestResult[]
function PlenaryNeotestAdapter.results(spec, result)
  -- TODO: Find out if this JSON option is supported in future
  local success, data = pcall(lib.files.read, spec.context.results_path)
  if not success then
    data = vim.json.encode({ pass = {}, fail = {}, errs = {}, fatal = {} })
  end
  ---@type PlenaryTestResults
  local plenary_results = vim.json.decode(data, { luanil = { object = true } })
  local results = {}
  for _, plen_result in pairs(plenary_results.pass) do
    local pos_id, pos_result = convert_plenary_result(plen_result, "passed", spec.context.file)
    results[pos_id] = pos_result
  end
  local file_result = { status = "passed", errors = {} }
  local failed = vim.list_extend({}, plenary_results.errs)
  vim.list_extend(failed, plenary_results.fail)
  vim.list_extend(failed, plenary_results.fatal) -- TODO: Verify shape
  for _, plen_result in pairs(failed) do
    local pos_id, pos_result = convert_plenary_result(plen_result, "failed", spec.context.file)
    results[pos_id] = pos_result
    file_result.status = "failed"
    vim.list_extend(file_result.errors, pos_result.errors)
  end
  results[spec.context.file] = file_result
  return results
end

setmetatable(PlenaryNeotestAdapter, {
  __call = function(_, opts)
    return PlenaryNeotestAdapter
  end,
})

return PlenaryNeotestAdapter
