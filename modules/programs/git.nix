{ config, ... }:
let
  inherit (config.meta) user;
in
{
  flake.modules.homeManager.git =
    { config, pkgs, ... }:
    let
      # Commit signing uses whichever enrolled YubiKey is plugged in: "-f
      # yubikey" becomes the non-resident handle for that key's serial.
      signer = pkgs.writeShellApplication {
        name = "git-ssh-keygen";
        runtimeInputs = [
          pkgs.yubikey-manager
          pkgs.openssh
        ];
        text = ''
          args=("$@")
          if [ "''${1:-}" = -Y ] && [ "''${2:-}" = sign ]; then
            for i in "''${!args[@]}"; do
              if [ "''${args[i]}" = -f ] && [ "''${args[i + 1]:-}" = yubikey ]; then
                key=
                for serial in $(timeout 10 ykman list --serials); do
                  candidate="$HOME/.ssh/id_ed25519_sk_sign_$serial"
                  if [ -f "$candidate" ]; then
                    key=$candidate
                    break
                  fi
                done
                if [ -z "$key" ]; then
                  echo "Connect an enrolled YubiKey to sign this Git operation." >&2
                  exit 1
                fi
                args[i + 1]=$key
              fi
            done
          fi
          exec ssh-keygen "''${args[@]}"
        '';
      };
    in
    {
      programs.git = {
        enable = true;
        signing = {
          format = "ssh";
          key = "yubikey";
          signByDefault = true;
          signer = "${signer}/bin/git-ssh-keygen";
          allowedSigners = "${config.xdg.configHome}/git/allowed_signers";
        };
        ignores = [
          "**/.claude/settings.local.json"
          ".direnv/"
        ];
        includes = [ { path = "${config.xdg.configHome}/theme/delta.gitconfig"; } ];
        settings = {
          user = {
            name = user.fullName;
            inherit (user) email;
          };
          core = {
            autocrlf = false;
            safecrlf = false;
            filemode = false;
            trustctime = false;
          };
          init.defaultBranch = "main";
          column.ui = "auto";
          branch = {
            sort = "-committerdate";
            autosetupRebase = "always";
          };
          fetch.prune = true;
          push = {
            default = "upstream";
            autoSetupRemote = true;
          };
          pull.rebase = true;
          rebase.autoStash = true;
          merge.conflictstyle = "diff3";
          mergetool.keepBackup = false;
          diff.tool = "nvimdiff";
          difftool = {
            prompt = false;
            trustExitCode = true;
          };
          help.autocorrect = 1;
          rerere.enabled = true;
          submodule.recurse = true;
          github.user = "evanriley";
          hub.protocol = "https";
          fsck.zeroPaddedFilemode = "ignore";
          alias = {
            st = "status --short --branch";
            sw = "switch";
            co = "checkout";
            cb = "checkout -b";
            cm = "commit -m";
            amend = "commit --amend --no-edit";
            unstage = "restore --staged";
            last = "log -1 HEAD --stat";
            lg = "log --oneline --decorate --graph --all";
            recent = "for-each-ref --sort=-committerdate --count=20 --format='%(refname:short)' refs/heads/";
          };
        };
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options.navigate = true;
      };

      xdg.configFile."git/allowed_signers".text = ''
        ${user.email} namespaces="git" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKvrBtmYXCnEIYTTlf1PjSkwrUU47CeNFEgq4hQ10vWi
        ${user.email} namespaces="git" sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIG4/+5iiwTb2yMz0zKuXGvnsiVAeFPm9jupcupEpBj9TAAAABHNzaDo= yubikey-20477902 sign
        ${user.email} namespaces="git" sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIC+8RZtgIbwq4UtSo+ggi6+NGfS1ZfMfudDYHlCUzbJJAAAABHNzaDo= yubikey-20477782 sign
      '';

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        matchBlocks."github.com" = {
          identitiesOnly = true;
          identityFile = [
            "~/.ssh/id_ed25519_sk_auth_20477902"
            "~/.ssh/id_ed25519_sk_auth_20477782"
          ];
        };
      };
    };
}
