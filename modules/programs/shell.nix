{
  flake.modules.nixos.shell = {
    programs.fish.enable = true;
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    documentation.man.cache.enable = true;
  };

  flake.modules.homeManager.shell =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        bat
        btop
        delta
        eza
        fastfetch
        fd
        fzf
        gh
        git
        jq
        lazygit
        man-pages
        mise
        neovim
        ripgrep
        rsync
        tmux
        tree-sitter
        unzip
        uv
        zoxide
      ];
    };
}
