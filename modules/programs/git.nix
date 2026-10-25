{ config, ... }:
let
  inherit (config.meta) user domain;
  oldDomain = "maybemaybe.lol";

  # git-bug's go-git SSH client needs every Gerrit host key type, not just ed25519.
  gerritKnownHosts = {
    programs.ssh.knownHosts = {
      gerrit-ed25519 = {
        hostNames = [
          "[git.${domain}]:29418"
          "[git.${oldDomain}]:29418"
        ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGOzrLcNC9G05r/TC3Gldb+gKLK+OZwmLN0xKVE2RIO";
      };
      gerrit-rsa = {
        hostNames = [
          "[git.${domain}]:29418"
          "[git.${oldDomain}]:29418"
        ];
        publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDti8boQ0FIEczXYuvDLS/Gd1BtRTE/Jv2vqFef/rUHmcWvmNQNG879fPGK8xlxqbIzQyp7DOu7dloFojez8mb+pGL5tZoOH2nukCGFm4eAx6eM8Q5GXjco9x8XuhTe7vyTUlSYxrsOe7GnziMThdJv/8LYba/FbLDOAOkD0fpdN98UO4maZ/TvVR5QMkbhKCzog90FS5R+j4t45agGIneQzmW+5LLUUe2T+0YzIaW1ol7pO7BskV9spGyFgsajkIt7xeBxbdrh7J/0Bfk8O7Z/AOT0F6oZM25VFV+xBTK1WlfGhltb1wAYR30MdcZRG5JRi7zkhE+zFd28Q6RBbjglFLqDaCEimUAbWyAgsFFF6GTVL0u4nRBoO97vw4JudNwcQsI89FMDEKixaJGVRogiYO1XQzlJkBT7zE79by/LUHMdHdOWmRCajix0s04ioSPt5K/W5xabh+AJH0jvd3Wd1iFhlgb2pWVxauWFGNZ37bbf4MKYTXnTJKvaF/7/FGM=";
      };
      gerrit-ecdsa = {
        hostNames = [
          "[git.${domain}]:29418"
          "[git.${oldDomain}]:29418"
        ];
        publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBL2Z4HWpKU6SpDOyIuavswlYDZljrV8CDofUqTISwn4LCfTeMXNJj+DzkEhbQQ1wYysPtZUXE9cfiHoTqMM54sQ=";
      };
    };
  };
in
{
  flake.modules.nixos.git = gerritKnownHosts;
  flake.modules.darwin.git = gerritKnownHosts;

  flake.modules.homeManager.git =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.packages = [
        pkgs.git-review
        pkgs.git-bug
      ];

      programs.git = {
        enable = true;
        ignores = [
          "**/.claude/settings.local.json"
          ".direnv/"
        ];
        includes = [
          { path = "${config.xdg.configHome}/theme/delta.gitconfig"; }
          {
            condition = "gitdir:~/maybe/";
            contents = {
              branch.main = {
                remote = "origin";
                merge = "refs/heads/main";
              };
              remote.origin.push = "HEAD:refs/for/main";
            };
          }
        ];
        settings = {
          user = {
            name = user.fullName;
            inherit (user) email;
          };
          core = {
            autocrlf = false;
            safecrlf = false;
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
            difft = "-c diff.external=${lib.getExe config.programs.difftastic.package} diff";
          };
        };
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options.navigate = true;
      };

      programs.difftastic = {
        enable = true;
        jujutsu.enable = true;
      };

      programs.jujutsu = {
        enable = true;
        settings = {
          user = {
            name = user.fullName;
            inherit (user) email;
          };
        };
      };

      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        settings =
          lib.genAttrs
            [
              "github.com"
              "git.${domain}"
              "git.${oldDomain}"
            ]
            (_: {
              # The keyring agent offers keys in its own order; read the files in this order instead.
              IdentityAgent = "none";
              IdentitiesOnly = "yes";
              IdentityFile = [
                "~/.ssh/id_ed25519"
                "~/.ssh/id_ed25519_sk_auth_20477902"
                "~/.ssh/id_ed25519_sk_auth_20477782"
              ];
            });
      };

      # git-bug's go-git SSH client authenticates only with agent keys.
      launchd.agents.ssh-add = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        enable = true;
        config = {
          ProgramArguments = [
            "/usr/bin/ssh-add"
            "${config.home.homeDirectory}/.ssh/id_ed25519"
          ];
          RunAtLoad = true;
        };
      };
    };
}
