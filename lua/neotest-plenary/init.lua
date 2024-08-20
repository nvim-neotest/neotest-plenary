local create_adapter = require("neotest-plenary.adapter")

local PlenaryNeotestAdapter = create_adapter({})

setmetatable(PlenaryNeotestAdapter, {
  __call = function(_, opts)
    opts = opts or {}
    return create_adapter({ min_init = opts.min_init })
  end,
})

PlenaryNeotestAdapter.setup = function(opts)
  return PlenaryNeotestAdapter(opts)
end

return PlenaryNeotestAdapter
