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
      dotfiles.config = [
        "btop"
        "fastfetch"
        "fish"
        "nvim"
        "tmux"
      ];

      home.packages = with pkgs; [
        bat
        btop
        eza
        fastfetch
        fd
        fzf
        gh
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
