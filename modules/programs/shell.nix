{ config, inputs, ... }:
let
  inherit (config.meta) user secrets;
  atuinKey = {
    file = secrets + "/atuin-key.age";
    owner = user.name;
  };
in
{
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
      # The hand-edited tmux config copies through wl-copy/wl-paste.
      macClipboard = [
        (pkgs.writeShellScriptBin "wl-copy" "exec /usr/bin/pbcopy")
        (pkgs.writeShellScriptBin "wl-paste" "exec /usr/bin/pbpaste")
      ];
      # Boots the tmux server at login so the mail session exists after
      # reboots. tmux.conf creates the mail session when the server starts;
      # the throwaway __autostart session only forces a fresh server up, and
      # the has-session guard covers a server that is already running.
      tmuxServerBoot = pkgs.writeShellScript "tmux-server-boot" ''
        ${pkgs.tmux}/bin/tmux new-session -A -d -s __autostart
        ${pkgs.tmux}/bin/tmux has-session -t =mail 2>/dev/null || ${pkgs.tmux}/bin/tmux new-session -d -s mail -n aerc aerc
        ${pkgs.tmux}/bin/tmux kill-session -t __autostart 2>/dev/null || true
      '';
    in
    {
      imports = [ inputs.nix-index-database.homeModules.nix-index ];

      dotfiles.config = [
        "fastfetch"
        "fish/functions"
        "tmux"
      ];

      home.sessionVariables = {
        EDITOR = "nvim";
        VISUAL = "nvim";
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
          t = "tmux new -A -s main";
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
      # Skipped on darwin: atuin's interactive PTY e2e tests fail there
      # (nixpkgs#573527, nixpkgs PR#574333 skips only the first; the rest of
      # the bash-preexec setup family fails the same way on macOS 27).
      # Drop this override once the nixpkgs pin contains a fix.
      programs.atuin.package = lib.mkIf isDarwin (
        pkgs.atuin.overrideAttrs (old: {
          checkFlags = old.checkFlags ++ [
            "--skip=filtered_commands_leave_no_captured_output"
            "--skip=setup_2_tests_shells_bash_preexec_toml"
          ];
        })
      );
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

      # Boot the tmux server at login so the mail session exists after
      # reboots.
      systemd.user.services.tmux-server = lib.mkIf (!isDarwin) {
        Unit.Description = "Start the tmux server and its mail session";
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${tmuxServerBoot}";
        };
        Install.WantedBy = [ "default.target" ];
      };

      # launchd does not inherit the profile, so PATH needs to cover aerc and
      # msmtpq inside the tmux server it starts.
      launchd.agents.tmux-server = lib.mkIf isDarwin {
        enable = true;
        config = {
          ProgramArguments = [ "${tmuxServerBoot}" ];
          EnvironmentVariables.PATH = "${config.home.homeDirectory}/.nix-profile/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          RunAtLoad = true;
        };
      };

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
          macClipboard
          ++ [
            # GNU ls for the aliases above.
            pkgs.coreutils
          ]
        )
        ++ (with pkgs; [
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
        ])
        ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
          amp
          claude-code
          codex
        ]);
    };
}
