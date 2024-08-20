local lib = require("neotest.lib")

local M = {}

function M.is_test_file(file_path)
  return vim.endswith(file_path, "_spec.lua")
end

function M.get_strategy_config(strategy, python, python_script, args)
  local config = {
    dap = nil, -- TODO: Add dap config
  }
  if config[strategy] then
    return config[strategy]()
  end
end

M.treesitter_query = [[
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

function M.get_script_path()
  local paths = vim.api.nvim_get_runtime_file("run_tests.lua", true)
  for _, path in ipairs(paths) do
    if vim.endswith(path, ("neotest-plenary%srun_tests.lua"):format(lib.files.sep)) then
      return path
    end
  end
end

return M
