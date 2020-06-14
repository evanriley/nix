{config, lib, pkgs, ...}:

{
  # enable unfree packages.
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = (with pkgs; [
    # basics
    wget curl jq htop p7zip which

    # vc
    git

    # utils
    rustfmt clang-tools graphviz ripgrep fzf starship
    gnupg pinentry

    # Wayland utils
    grim slurp wf-recorder wl-clipboard


    # X utils
    xclip maim slop lxrandr xscreensaver

    # Build systems
    gnumake cmake gradle

    # nix utils
    nix-prefetch-scripts nix-du

    # Languages
    nodejs clojure leiningen clj-kondo rustup cargo rls
    go julia python27 python3 elixir

    # games & stuff
    steam steam-run discord

    # browsers
    firefox google-chrome chromium

    # terminal and editors
    kitty alacritty neovim vim

    # CLI a/v stuff
    ffmpeg imagemagick

    # networking
    openssh networkmanagerapplet

    # other
    bitwarden

  ]);
}
