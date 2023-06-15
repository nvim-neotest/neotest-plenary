local lib = require("neotest.lib")

local M = {}

function M.is_test_file(file_path)
  return vim.endswith(file_path, "_spec.lua")
end

function M.get_strategy_config(strategy)
  local config = {
    dap = function()
      return vim.tbl_extend("keep", {
        type = "nlua",
        request = "attach",
        name = "Neotest Debugger",
        host = "127.0.0.1",
        port = 8086,
      }, dap_args or {})
    end,
  }
  if config[strategy] then
    return config[strategy]()
  end
end

return M
