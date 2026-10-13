{ config, ... }:
let
  inherit (config.flake.lib) mkScript;
in
{
  flake.modules.nixos.emacs = {
    programs.nix-ld.enable = true;
  };

  flake.modules.homeManager.emacs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      emacsPackage = if isLinux then pkgs.emacs31-pgtk else pkgs.emacs31;
      muBinary = "${pkgs.mu}/bin/mu";
      # en-computers and en-science are removal throws in the pinned nixpkgs
      # ("upstream url pointed to a gambling website" / "upstream was removed").
      aspellEnv = pkgs.aspellWithDicts (d: [ d.en ]);
      # nixpkgs' parinfer-rust is 0.4.3 with the wrong filename; the Doom
      # parinfer module needs exactly this 0.4.7 release asset.
      parinferRustLibrary = pkgs.fetchurl {
        url = "https://github.com/justinbarclay/parinfer-rust-emacs/releases/download/v0.4.7/parinfer-rust-${
          if isLinux then "linux" else "darwin"
        }.so";
        hash =
          if isLinux then
            "sha256-updXagsnsqsBVYMZ1GvBWcp8X7jGdo89ai9aiE7tI6Y="
          else
            "sha256-6RyisAv6QoLgREB00qGUNqCcnGhDkOc3UYo+iJn31dU=";
      };
    in
    {
      programs.emacs = {
        enable = true;
        package = emacsPackage;
        # mu4e propagates mu; the rest are needed on PATH for launchd, which
        # does not inherit the user profile (mu4e, spell, and ruff run them).
        extraPackages = epkgs: [
          epkgs.mu4e
          pkgs.git
          pkgs.isync
          pkgs.msmtp
          pkgs.ruff
          aspellEnv
        ];
      };

      services.emacs.enable = true;
      services.emacs.extraOptions = [
        "--init-directory=${config.home.homeDirectory}/.config/emacs"
      ];

      # launchd does not source the profile, so the darwin daemon needs these
      # explicitly; the Linux daemon gets sessionVariables via the systemd
      # user environment (environment.d), not its login shell.
      launchd.agents.emacs.config.EnvironmentVariables = lib.mkIf (!isLinux) {
        PARINFER_RUST_LIBRARY = "${parinferRustLibrary}";
        MU4E_MU_BINARY = muBinary;
      };

      home.packages =
        with pkgs;
        [
          mu
          rust-analyzer
          gopls
          zls
          clang-tools
          jdt-language-server
          clojure-lsp
          nerd-fonts.symbols-only
          # Python linter/formatter LSP, matching the nvim setup.
          ruff
          aspellEnv
        ]
        ++ lib.optional isLinux gcc
        ++ [
          (mkScript pkgs {
            name = "doom-bootstrap";
            src = ./_emacs/doom-bootstrap;
            runtimeInputs = [ pkgs.git ];
          })
          (mkScript pkgs {
            name = "doom-upgrade";
            src = ./_emacs/doom-upgrade;
            runtimeInputs = [ pkgs.git ];
          })
          # The profile bin is on PATH in every shell; sessionPath only reaches
          # shells after their next login.
          (pkgs.writeShellScriptBin "doom" ''
            if [ ! -x "$HOME/.config/emacs/bin/doom" ]; then
              echo "doom: not bootstrapped; run doom-bootstrap first" >&2
              exit 1
            fi
            exec "$HOME/.config/emacs/bin/doom" "$@"
          '')
        ];

      dotfiles.config = [ "doom" ];

      home.sessionPath = [ "${config.home.homeDirectory}/.config/emacs/bin" ];

      home.sessionVariables.MU4E_MU_BINARY = muBinary;
      home.sessionVariables.PARINFER_RUST_LIBRARY = "${parinferRustLibrary}";
    };
}
