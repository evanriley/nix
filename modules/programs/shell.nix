{ config, inputs, ... }:
let
  inherit (config.meta) user;
  inherit (config.flake.lib) macClipboard;
  atuinKey = {
    file = inputs.self + "/secrets/atuin-key.age";
    owner = user.name;
  };
in
{
  # The hand-edited kak and tmux configs and qute-cleanurl copy through wl-copy/wl-paste.
  flake.lib.macClipboard = pkgs: [
    (pkgs.writeShellScriptBin "wl-copy" "exec /usr/bin/pbcopy")
    (pkgs.writeShellScriptBin "wl-paste" "exec /usr/bin/pbpaste")
  ];

  flake.modules.nixos.shell =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
      users.users.${user.name}.shell = pkgs.fish;
      age.secrets.atuin-key = atuinKey;
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    };

  flake.modules.darwin.shell =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
      users.users.${user.name}.shell = pkgs.fish;
      age.secrets.atuin-key = atuinKey;
    };

  flake.modules.homeManager.shell =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
    in
    {
      imports = [ inputs.nix-index-database.homeModules.nix-index ];

      dotfiles.config = [
        "fastfetch"
        "fish/functions"
        "tmux"
      ];

      home.sessionVariables = {
        EDITOR = "kak";
        VISUAL = "kak";
      };
      # environment.d rejects empty values such as FZF_CTRL_R_COMMAND.
      systemd.user.sessionVariables = lib.filterAttrs (_: v: v != "") config.home.sessionVariables;

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

      programs.fzf = {
        enable = true;
        # Leaves CTRL-R to Atuin.
        historyWidget.command = "";
      };
      programs.atuin = {
        enable = true;
        flags = [ "--disable-up-arrow" ];
        settings = {
          update_check = false;
          key_path = "/run/agenix/atuin-key";
        };
      };
      programs.nix-your-shell.enable = true;
      programs.zoxide.enable = true;
      programs.nix-index.enable = true;
      programs.nix-index-database.comma.enable = true;

      programs.btop = {
        enable = true;
        settings = {
          color_theme = "monobiome";
          theme_background = false;
          show_battery = false;
          save_config_on_exit = false;
        };
      };

      # NixOS provides direnv system-wide.
      programs.direnv = lib.mkIf isDarwin {
        enable = true;
        nix-direnv.enable = true;
      };

      home.packages =
        lib.optionals isDarwin (
          macClipboard pkgs
          ++ [
            # GNU ls for the aliases above.
            pkgs.coreutils
          ]
        )
        ++ (with pkgs; [
          bat
          codex
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
        ])
        ++ [ inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code ];
    };
}
