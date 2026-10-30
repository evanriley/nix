{ inputs, ... }:
{
  perSystem =
    { lib, system, ... }:
    lib.mkIf (system == "x86_64-linux") (
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            package:
            builtins.elem (lib.getName package) [
              "helium"
              "widevine-cdm"
            ];
        };
        release = lib.importJSON ./helium.json;

        deps = with pkgs; [
          alsa-lib
          at-spi2-atk
          at-spi2-core
          atk
          bzip2
          cairo
          coreutils
          cups
          curl
          dbus
          expat
          flac
          fontconfig
          freetype
          gcc-unwrapped.lib
          gdk-pixbuf
          glib
          gtk3
          gtk4
          harfbuzz
          icu
          libcap
          libdrm
          liberation_ttf
          libexif
          libglvnd
          libkrb5
          libpng
          libpulseaudio
          libva
          libx11
          libxcb
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxkbcommon
          libxrandr
          libxrender
          libxscrnsaver
          libxshmfence
          libxtst
          libgbm
          nspr
          nss
          (libopus.override { withCustomModes = true; })
          pango
          pciutils
          pipewire
          snappy
          speechd-minimal
          systemdLibs
          util-linux
          vulkan-loader
          wayland
          wget
        ];

        makeHelium =
          {
            withWidevine ? true,
          }:
          pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
            pname = "helium";
            inherit (release) version;

            src = pkgs.fetchurl {
              url = "https://github.com/imputnet/helium-linux/releases/download/${finalAttrs.version}/helium-${finalAttrs.version}-x86_64_linux.tar.xz";
              inherit (release) hash;
            };

            nativeBuildInputs = [
              pkgs.makeWrapper
              pkgs.patchelf
            ];

            buildInputs = [
              pkgs.adwaita-icon-theme
              pkgs.glib
              pkgs.gtk3
              pkgs.gtk4
              pkgs.gsettings-desktop-schemas
            ];

            rpath = lib.makeLibraryPath deps + ":" + lib.makeSearchPathOutput "lib" "lib64" deps;
            binpath = lib.makeBinPath deps;

            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin $out/share/helium $out/share/applications $out/share/icons/hicolor/256x256/apps
              cp -a . $out/share/helium
              cd $out/share/helium

              for elf in helium helium_crashpad_handler chromedriver; do
                patchelf --set-rpath "$rpath" $elf
                patchelf --set-interpreter ${pkgs.bintools.dynamicLinker} $elf
              done

              rm libvulkan.so.1
              ln -s ${lib.getLib pkgs.vulkan-loader}/lib/libvulkan.so.1 libvulkan.so.1

              mv helium.desktop $out/share/applications/helium.desktop
              substituteInPlace $out/share/applications/helium.desktop \
                --replace-fail 'Exec=helium' "Exec=$out/bin/helium"
              mv product_logo_256.png $out/share/icons/hicolor/256x256/apps/helium.png

              ${lib.optionalString withWidevine ''
                ln -s ${pkgs.widevine-cdm}/share/google/chrome/WidevineCdm WidevineCdm
              ''}

              makeWrapper $out/share/helium/helium-wrapper $out/bin/helium \
                --prefix LD_LIBRARY_PATH : "$rpath" \
                --prefix PATH : "$binpath" \
                --suffix PATH : "${lib.makeBinPath [ pkgs.xdg-utils ]}" \
                --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH:${pkgs.addDriverRunpath.driverLink}/share" \
                --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

              runHook postInstall
            '';

            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck
              $out/bin/helium --version | grep -F ${finalAttrs.version}
              runHook postInstallCheck
            '';

            meta = {
              description = "Privacy-focused Chromium-based web browser";
              homepage = "https://helium.computer";
              license = [
                lib.licenses.gpl3Only
              ]
              ++ lib.optional withWidevine pkgs.widevine-cdm.meta.license;
              sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" ];
              mainProgram = "helium";
            };
          });
      in
      {
        packages.helium = lib.makeOverridable makeHelium { };

        packages.helium-update = pkgs.writeShellApplication {
          name = "helium-update";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.curl
            pkgs.jq
            pkgs.sequoia-sqv
          ];
          text = ''
            if [ "$#" -ne 1 ]; then
              echo "usage: helium-update <path to helium.json>" >&2
              exit 2
            fi
            release_file=$1
            repo=imputnet/helium-linux

            if ! current=$(jq -er .version "$release_file"); then
              echo "reading .version from $release_file failed; expected a JSON file with version and hash. Check the file, then run helium-update again" >&2
              exit 1
            fi

            if ! latest=$(curl -fsS "https://api.github.com/repos/$repo/releases/latest" | jq -er .tag_name); then
              echo "fetching the latest release of $repo from api.github.com failed; $release_file is unchanged. Check the network and the GitHub API rate limit, then run helium-update again" >&2
              exit 1
            fi
            if ! [[ $latest =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
              echo "the latest release tag of $repo is '$latest', expected four dot-separated numbers; $release_file is unchanged. Check the release, then run helium-update again" >&2
              exit 1
            fi

            if [ "$latest" = "$current" ]; then
              echo "helium $current is up to date"
              exit 0
            fi

            workdir=$(mktemp -d)
            trap 'rm -rf "$workdir"' EXIT
            tarball=helium-$latest-x86_64_linux.tar.xz
            url=https://github.com/$repo/releases/download/$latest/$tarball
            if ! curl -fsSL --output "$workdir/$tarball" "$url" \
              || ! curl -fsSL --output "$workdir/$tarball.asc" "$url.asc"; then
              echo "downloading $url and its .asc failed; $release_file is unchanged. Check the release assets, then run helium-update again" >&2
              exit 1
            fi

            if ! sqv --keyring ${./helium-signing-key.asc} "$workdir/$tarball.asc" "$workdir/$tarball"; then
              echo "verifying the signature of $tarball against the pinned key failed; $release_file is unchanged. Do not install this release unless the signing key rotated and was re-pinned in helium-signing-key.asc" >&2
              exit 1
            fi

            hash=sha256-$(sha256sum "$workdir/$tarball" | cut -d' ' -f1 | tr a-f A-F | basenc --base16 -d | base64 -w0)
            jq -n --arg version "$latest" --arg hash "$hash" '{version: $version, hash: $hash}' >"$workdir/helium.json"
            mv "$workdir/helium.json" "$release_file"
            echo "helium $current -> $latest"
          '';
        };
      }
    );
}
