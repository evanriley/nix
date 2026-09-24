{ inputs, ... }:
{
  flake.modules.homeManager.neovim =
    { pkgs, ... }:
    let
      inherit (inputs.nvf.lib.nvim.dag) entryAfter;
      map = mode: key: action: desc: {
        inherit
          mode
          key
          action
          desc
          ;
        silent = false;
      };
    in
    {
      imports = [ inputs.nvf.homeManagerModules.default ];

      programs.nvf = {
        enable = true;
        defaultEditor = false;
        settings.vim = {
          viAlias = false;
          vimAlias = false;

          globals = {
            mapleader = " ";
            maplocalleader = ",";
            parinfer_filetypes = [ "clojure" ];
            parinfer_no_maps = true;
            monobiome_themes = "${inputs.monobiome}/app-config/nvim";
          };

          options = {
            number = true;
            relativenumber = true;
            signcolumn = "yes";
            cursorline = true;
            expandtab = true;
            shiftwidth = 2;
            tabstop = 2;
            smartindent = true;
            wrap = false;
            linebreak = true;
            ignorecase = true;
            smartcase = true;
            undofile = true;
            splitright = true;
            splitbelow = true;
            splitkeep = "screen";
            termguicolors = true;
            winborder = "rounded";
            smoothscroll = true;
            confirm = true;
            inccommand = "split";
            updatetime = 250;
            timeoutlen = 300;
            completeopt = "menuone,noselect,popup,fuzzy";
            autocomplete = true;
            autocompletedelay = 100;
            foldmethod = "expr";
            foldexpr = "v:lua.vim.treesitter.foldexpr()";
            foldlevelstart = 99;
            foldlevel = 99;
            pumheight = 10;
            scrolloff = 8;
            sidescrolloff = 8;
            mouse = "a";
            list = true;
            clipboard = "unnamedplus";
            showmode = false;
            showtabline = 2;
            laststatus = 3;
          };

          treesitter = {
            enable = true;
            # Clojure indentation is parinfer's; help has none.
            indent.excludes = [
              "clojure"
              "help"
            ];
            grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
              bash
              c
              clojure
              cpp
              fish
              gleam
              lua
              markdown
              markdown_inline
              ocaml
              ocaml_interface
              python
              rust
              vimdoc
              zig
            ];
          };

          mini = {
            ai.enable = true;
            bracketed.enable = true;
            bufremove.enable = true;
            diff.enable = true;
            extra.enable = true;
            git.enable = true;
            icons.enable = true;
            jump.enable = true;
            jump2d.enable = true;
            notify.enable = true;
            pairs.enable = true;
            pick.enable = true;
            surround.enable = true;
            tabline.enable = true;
            trailspace.enable = true;
            statusline = {
              enable = true;
              setupOpts.use_icons = true;
            };
            sessions = {
              enable = true;
              setupOpts = {
                autoread = false;
                autowrite = false;
                file = "";
              };
            };
            move = {
              enable = true;
              setupOpts.mappings = {
                left = "<M-Left>";
                right = "<M-Right>";
                down = "<M-Down>";
                up = "<M-Up>";
                line_left = "<M-Left>";
                line_right = "<M-Right>";
                line_down = "<M-Down>";
                line_up = "<M-Up>";
              };
            };
          };

          utility = {
            oil-nvim = {
              enable = true;
              setupOpts.default_file_explorer = true;
            };
            undotree.enable = true;
          };

          repl.conjure.enable = true;

          extraPlugins = with pkgs.vimPlugins; {
            mini-input = {
              package = mini-input;
              setup = "require('mini.input').setup()";
            };
            render-markdown = {
              package = render-markdown-nvim;
              setup = "require('render-markdown').setup({})";
            };
            # Set up from config.lua: their options need Lua functions.
            mini-snippets.package = mini-snippets;
            mini-clue.package = mini-clue;
            nvim-lspconfig.package = nvim-lspconfig;
            nvim-dap.package = nvim-dap;
            nvim-parinfer.package = nvim-parinfer;
            nvim-treesitter-endwise.package = nvim-treesitter-endwise;
            friendly-snippets.package = friendly-snippets;
          };

          # nvf writes globals as vim.g.<name>, which cannot express "#".
          luaConfigPre = "vim.g['conjure#filetypes'] = { 'clojure' }";

          additionalRuntimePaths = [ ./_neovim ];
          luaConfigRC.config = entryAfter [ "pluginConfigs" ] (builtins.readFile ./_neovim/config.lua);

          keymaps = [
            (map "n" "<A-h>" "<Cmd>vertical resize -2<CR>" "Narrower")
            (map "n" "<A-j>" "<Cmd>resize +2<CR>" "Taller")
            (map "n" "<A-k>" "<Cmd>resize -2<CR>" "Shorter")
            (map "n" "<A-l>" "<Cmd>vertical resize +2<CR>" "Wider")
            (map "n" "<C-h>" "<C-w>h" "Window left")
            (map "n" "<C-j>" "<C-w>j" "Window down")
            (map "n" "<C-k>" "<C-w>k" "Window up")
            (map "n" "<C-l>" "<C-w>l" "Window right")
            (map "n" "<C-\\>" "<C-w>p" "Previous window")
            (map "n" "<leader>m" "<Cmd>RenderMarkdown toggle<CR>" "Toggle markdown render")
            (map "n" "-" "<Cmd>Oil<CR>" "Open parent directory")
            (map "t" "<Esc><Esc>" "<C-\\><C-n>" "Exit terminal mode")
            (map "n" "<Esc>" "<Cmd>nohlsearch<CR>" "Clear search highlight")
            (map "n" "<leader>w" "<Cmd>w<CR>" "Save file")
            (map "n" "<leader>u" "<Cmd>UndotreeToggle<CR>" "Toggle undotree")
            (map "n" "<leader>cw" "<Cmd>lua MiniTrailspace.trim()<CR>" "Trim trailing whitespace")
            (map "n" "<leader>G" "<Cmd>botright 15split | terminal lazygit<CR>" "Lazygit")
          ];
        };
      };
    };
}
