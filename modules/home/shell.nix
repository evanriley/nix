{ config, pkgs, lib, ... }:

{
  # Use neovim for editing
  environment.variables = {
    EDITOR = lib.mkOverride 900 "nvim";
    PROJECTS = "~/Code";
    TERMINAL = "kitty";
  };

  # use zsh
  programs.zsh = {
    enable = true;

    shellAliases = {
      vim = "nvim";

      grep = "grep --color=auto";
      egrep = "egrep --color=auto";
      fgrep = "fgrep --color=auto";

      mkdir = "mkdir -pv";

      wget =  "wget -c";

      # ... never use this
      gac = "git add . && git commit -a -m ";

      # wtf is my ip
      myip = "curl http://ipecho.net/plain; echo";

      # nix command to make things easier
      sysa = "sudo nixos-rebuild switch";
      sysu = "sudio nix-channel --update; sysa";
      sysclean = "sudo nix-collect-garbage -d; and sudo nix-store --optimise";

    };

    promptInit = ''
      eval "$(starship init zsh)"
    '';
  };
}
