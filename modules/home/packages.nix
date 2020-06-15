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
    rustfmt graphviz ripgrep fzf starship
    gnupg pinentry-qt coreutils coreutils-prefixed
    sqlite fd openrazer-daemon

    # Wayland utils
    grim slurp wf-recorder wl-clipboard


    # X utils
    xclip maim slop lxrandr xscreensaver

    # Build systems
    gnumake cmake gradle meson ninja pkg-config
    clang clang-tools llvm

    # nix utils
    nix-prefetch-scripts nix-du

    # Languages
    nodejs clojure leiningen clj-kondo rustup cargo rls
    go julia python27 python3 elixir

    # multimedia
    steam steam-run discord
    spotify

    # browsers
    firefox google-chrome chromium

    # terminal and editors
    kitty alacritty neovim vim
    emacs

    # CLI a/v stuff
    ffmpeg imagemagick

    # networking
    openssh networkmanagerapplet

    # fonts
    source-code-pro

    # other
    bitwarden bitwarden-cli

  ]);
}
