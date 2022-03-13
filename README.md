# neotest-plenary

[Neotest](https://github.com/rcarriga/neotest) adapter for [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) busted tests.

![image](https://user-images.githubusercontent.com/24252670/158066001-713829a6-c515-4dbe-84eb-3a486a3142d5.png)

This is WIP as use cases are discovered. Currently any `minimal_init.lua/vim` will be used when running tests.
If you have extra requirements for running tests, please raise an issue to discuss incorporating it into this adapter.

```lua
require("neotest").setup({
  adapters = {
    require("neotest-plenary")
  }
})
```
