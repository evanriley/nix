{config, lib, pkgs, ...}:


{
  # enable unfree packages.
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = (with pkgs; [
    # basics
    wget curl jq htop p7zip which
    tree bash_5

    # vc
    git

    # utils
    rustfmt graphviz ripgrep fzf starship
    gnupg pinentry-qt coreutils coreutils-prefixed
    sqlite fd
    neofetch

    # Wayland utils
    grim slurp wf-recorder wl-clipboard


    # X utils
    xclip maim slop lxrandr xscreensaver
    glxinfo

    # Build systems
    gnumake cmake gradle meson ninja pkg-config
    clang clang-tools llvm

    # nix utils
    nix-prefetch-scripts nix-du

    # Languages
    nodejs clojure leiningen clj-kondo rustup cargo rls
    go julia python27 python3 elixir adoptopenjdk-bin

    # multimedia and chats
    steam steam-run discord
    spotify spotifyd spotify-tui
    mpv slack

    # browsers
    firefox google-chrome chromium

    # terminal and editors
    kitty alacritty neovim vim
    emacs

    # CLI a/v stuff
    ffmpeg imagemagick

    # networking
    openssh networkmanagerapplet

    # other
    bitwarden bitwarden-cli
    obs-studio obs-wlrobs

  ]);

  fonts.fonts = with pkgs; [
    source-code-pro
    fira-code
  ];
}
