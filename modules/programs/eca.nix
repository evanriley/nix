{ config, inputs, ... }:
let
  inherit (config.meta) user;
  ecaNetrc = {
    file = inputs.self + "/secrets/eca-netrc.age";
    owner = user.name;
  };
in
{
  flake.modules.nixos.eca.age.secrets.eca-netrc = ecaNetrc;

  flake.modules.darwin.eca.age.secrets.eca-netrc = ecaNetrc;

  flake.modules.homeManager.eca =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      isLinux = pkgs.stdenv.hostPlatform.isLinux;
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

      serverVersion = "0.163.1";
      desktopVersion = "0.10.3";

      ecaServer = pkgs.stdenv.mkDerivation {
        pname = "eca";
        version = serverVersion;
        src = pkgs.fetchurl {
          url = "https://github.com/editor-code-assistant/eca/releases/download/${serverVersion}/eca-native-${
            if isLinux then "static-linux-amd64" else "macos-aarch64"
          }.zip";
          hash =
            if isLinux then
              "sha256-yzesKVPBSA/zFeaywVtK/y9fAasiuEPuONIcEkW10hY="
            else
              "sha256-3+wZ6RG/9t3S4wWFLNLuxAodJiZ93jo2etAwG3+b7uQ=";
        };
        nativeBuildInputs = [ pkgs.unzip ];
        dontUnpack = true;
        installPhase = ''
          unzip -p $src eca > eca
          install -Dm755 eca $out/bin/eca
        '';
        doInstallCheck = isLinux;
        installCheckPhase = ''
          $out/bin/eca --version | grep -q "${serverVersion}"
        '';
        meta.mainProgram = "eca";
      };

      ecaDesktopSrc = pkgs.fetchurl {
        url = "https://github.com/editor-code-assistant/eca-desktop/releases/download/v${desktopVersion}/eca-linux-x86_64.AppImage";
        hash = "sha256-fEYyFUZBEzWtYqEuJHmSePfU/OS5IgVQpwrpNgLuYqM=";
      };
      ecaDesktopContents = pkgs.appimageTools.extract {
        pname = "eca-desktop";
        version = desktopVersion;
        src = ecaDesktopSrc;
      };
      ecaDesktop = pkgs.appimageTools.wrapType2 {
        pname = "eca-desktop";
        version = desktopVersion;
        src = ecaDesktopSrc;
        extraInstallCommands = ''
          install -Dm444 ${ecaDesktopContents}/eca-desktop.desktop \
            $out/share/applications/eca-desktop.desktop
          substituteInPlace $out/share/applications/eca-desktop.desktop \
            --replace-fail 'Exec=AppRun' 'Exec=eca-desktop'
          for size in 16 32 64 128 256 512; do
            install -Dm444 ${ecaDesktopContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/eca-desktop.png \
              $out/share/icons/hicolor/''${size}x''${size}/apps/eca-desktop.png
          done
        '';
        meta = {
          description = "ECA Desktop - AI code assistant";
          homepage = "https://eca.dev";
          license = lib.licenses.asl20;
          platforms = [ "x86_64-linux" ];
          mainProgram = "eca-desktop";
        };
      };

      ecaDesktopDmg = pkgs.fetchurl {
        url = "https://github.com/editor-code-assistant/eca-desktop/releases/download/v${desktopVersion}/eca-mac-arm64.dmg";
        hash = "sha256-2sQ9/ImbDU4mPlCCC4ZtYeGMNlX35jUj+YfydNhXm5c=";
      };
    in
    {
      programs.emacs.extraPackages = _: [ ecaServer ];

      home.packages = lib.optional isLinux ecaDesktop;

      dotfiles.config = [ "eca" ];

      home.activation.ecaDesktop = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          app="$HOME/Applications/ECA.app"
          marker="$HOME/.local/state/eca-desktop/version"
          if [ -d "$app" ] && [ -f "$marker" ] && [ "$(cat "$marker")" = "${desktopVersion}" ]; then
            :
          else
            mountpoint="$(mktemp -d)"
            if hdiutil attach -nobrowse -readonly -mountpoint "$mountpoint" ${ecaDesktopDmg}; then
              run mkdir -p "$HOME/Applications"
              run rm -rf "$app"
              run cp -R "$mountpoint/ECA.app" "$HOME/Applications/"
              hdiutil detach "$mountpoint" >/dev/null 2>&1 || true
              run mkdir -p "$(dirname "$marker")"
              printf '%s\n' "${desktopVersion}" > "$marker"
            else
              errorEcho "eca-desktop: could not mount ${ecaDesktopDmg}; leaving $app unchanged"
            fi
            rmdir "$mountpoint" 2>/dev/null || true
          fi
        ''
      );
    };
}
