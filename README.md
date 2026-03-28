# vis-treesitter

A standalone tree-sitter plugin for [vis](https://github.com/martanne/vis).
This little plugin brings the tree-sitter integration out of vis's core so that you can install it as a standard plugin, remaining compatible with older or baseline `vis` installations.

## Installation

1. Clone this repository into your vis plugins directory (`~/.config/vis/plugins/vis-treesitter`).
2. Make sure you have `tree-sitter` and `lua` development headers installed on your system, then, compile the native Lua extension:
```sh
cd ~/.config/vis/plugins/vis-treesitter
make # or make static for statically linked lib
```
3. Load the plugin in your `visrc.lua`:
```lua
require('plugins/vis-treesitter')
```

## Usage

For this plugin to work for a certain language, you need two things:
- Tree sitter query files (.scm)
- Compiled grammar (.so)

For a language, put it's compiled `<LANG>.so` under one of the following directories:
+ `~/.local/lib/tree-sitter/`
+ `/usr/lib/tree-sitter/`
+ `/usr/local/lib/tree-sitter/`

and it's `<LANG>.scm` file under `~/.config/vis/plugins/vis-treesitter/queries/`.
