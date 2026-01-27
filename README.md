# go-type-hover.nvim

Go nested type hover for Neovim. Inspect Go type definitions in floating windows and navigate into nested types without leaving the current buffer.

## Requirements

- Neovim with built-in LSP
- `gopls` running for Go buffers

## Install

Lazy.nvim

```lua
{
  "phergul/go-type-hover.nvim",
}
```

## Usage

- `gK` in a Go buffer: open the type definition under cursor in a float

Navigation within floats uses vim keybindings:

- `l` / `Enter` enter the nested type under cursor
- `h` go back (close the top float)
- `q` / `Esc` close all floats
- `j` / `k` move within the float

## Configuration

```lua
require("go_type_hover").setup({
  keymap = "gK",
  anchor = "cursor",
  float = {
    border = "rounded",
    focusable = true,
    max_width = 80,
    max_height = nil,
  },
  offset = { row = 1, col = 2 },
  ignored = { "context" },
})
```

Set `keymap = false` to disable the default keymap.
Set `anchor = "editor"` to anchor the first float to the editor instead of the cursor.
