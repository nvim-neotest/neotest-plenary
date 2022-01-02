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

return M
