return {
  "jonroosevelt/gemini-cli.nvim",
  -- Only load when the Gemini CLI is actually installed; otherwise its setup()
  -- blocks startup with an "Install it now? (y/n)" prompt every time.
  cond = function()
    return vim.fn.executable("gemini") == 1
  end,
  config = function()
    require("gemini").setup()
  end,
}
