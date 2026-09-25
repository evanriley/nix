{ config, inputs, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.nixos.shell =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
      users.users.${user.name}.shell = pkgs.fish;
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    };

  flake.modules.homeManager.shell =
    { config, pkgs, ... }:
    {
      imports = [ inputs.nix-index-database.homeModules.nix-index ];

      # Prompt and functions stay hand-edited; config.fish is generated below.
      dotfiles.config = [
        "fastfetch"
        "fish/functions"
        "tmux"
      ];

      home.sessionVariables = {
        EDITOR = "kak";
        VISUAL = "kak";
      };
      systemd.user.sessionVariables = config.home.sessionVariables;

      programs.fish = {
        enable = true;
        shellAliases = {
          vim = "nvim";
          ".." = "cd ..";
          "..." = "cd ../..";
          "...." = "cd ../../..";
          "....." = "cd ../../../..";
          ls = "ls --color=auto";
          grep = "grep --color=auto";
          diff = "diff --color=auto";
          ip = "ip -c";
          ll = "ls -lah";
          la = "ls -A";
          l = "ls -CF";
          clj-repl = ''clj "-J-Dclojure.server.repl={:port 5555 :accept clojure.core.server/repl :server-daemon false}"'';
          nrepl = ''clojure -Sdeps '{:deps {nrepl/nrepl {:mvn/version "1.7.0"}}}' -M -m nrepl.cmdline --interactive'';
        };
        interactiveShellInit = ''
          set -g fish_greeting
          fish_vi_key_bindings insert
          set -g fish_cursor_default block
          set -g fish_cursor_insert line
          set -g fish_cursor_replace_one underscore
          set -g fish_cursor_replace underscore
          set -g fish_cursor_visual block
          source ${config.xdg.configHome}/theme/fzf.fish
          if command -q opam
              opam env --shell=fish 2>/dev/null | source
          end
        '';
      };

      programs.fzf.enable = true;
      programs.zoxide.enable = true;
      programs.nix-index.enable = true;
      programs.nix-index-database.comma.enable = true;

      programs.btop = {
        enable = true;
        settings = {
          color_theme = "${config.xdg.configHome}/theme/btop.theme";
          theme_background = false;
          show_battery = false;
          save_config_on_exit = false;
        };
      };

      home.packages = with pkgs; [
        bat
        devenv
        eza
        fastfetch
        fd
        gh
        jq
        lazygit
        man-pages
        ripgrep
        rsync
        tmux
        tree-sitter
        unzip
        uv
      ];
    };
}
