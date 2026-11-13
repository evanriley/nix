_:
let
  readPin = file: builtins.fromJSON (builtins.readFile file);
in
{
  flake.lib = {
    pinVersion = file: (readPin file).version;

    fetchPin =
      pkgs: file: asset:
      let
        pin = readPin file;
      in
      pkgs.fetchurl {
        url = builtins.replaceStrings [ "{version}" ] [ pin.version ] pin.assets.${asset}.url;
        inherit (pin.assets.${asset}) hash;
      };
  };

  perSystem =
    { pkgs, ... }:
    {
      packages.pin-update = pkgs.writeShellApplication {
        name = "pin-update";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.jq
        ];
        text = ''
          if [ "$#" -lt 1 ]; then
            echo "usage: pin-update <pin.json>..." >&2
            exit 2
          fi

          update_pin() {
            local file=$1 name current source tag_prefix endpoint field latest tag temporary new key url hash

            name=$(basename "$file" .json)
            if ! current=$(jq -er .version "$file") \
              || ! source=$(jq -er .source "$file") \
              || ! tag_prefix=$(jq -er .tagPrefix "$file"); then
              echo "reading .source, .tagPrefix and .version from $file failed; expected a pin JSON file. Check the file, then run pin-update again" >&2
              return 1
            fi

            case $source in
              github:*)
                endpoint=https://api.github.com/repos/''${source#github:}/releases/latest
                field=.tag_name
                ;;
              npm:*)
                endpoint=https://registry.npmjs.org/''${source#npm:}/latest
                field=.version
                ;;
              *)
                echo "the source '$source' in $file is neither github:<owner>/<repo> nor npm:<name>; $file is unchanged. Fix the source, then run pin-update again" >&2
                return 1
                ;;
            esac

            if ! tag=$(curl -fsS "$endpoint" | jq -er "$field"); then
              echo "fetching the latest release of $source from $endpoint failed; $file is unchanged. Check the network and the API rate limit, then run pin-update again" >&2
              return 1
            fi
            latest=''${tag#"$tag_prefix"}
            if ! [[ $latest =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
              echo "the latest release of $source is '$tag', expected dot-separated numbers after the prefix '$tag_prefix'; $file is unchanged. Check the release, then run pin-update again" >&2
              return 1
            fi

            if [ "$latest" = "$current" ] || [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)" != "$latest" ]; then
              echo "$name $current is up to date"
              return 0
            fi

            new=$(<"$file")
            while IFS= read -r key; do
              url=$(jq -er --arg key "$key" '.assets[$key].url' "$file")
              url=''${url//\{version\}/$latest}
              if ! hash=$(nix store prefetch-file --json "$url" | jq -er .hash); then
                echo "prefetching $url failed; $file is unchanged. Check the release assets, then run pin-update again" >&2
                return 1
              fi
              new=$(jq --arg key "$key" --arg hash "$hash" '.assets[$key].hash = $hash' <<<"$new")
            done < <(jq -r '.assets | keys_unsorted[]' "$file")
            new=$(jq --arg version "$latest" '.version = $version' <<<"$new")

            temporary=$(mktemp)
            printf '%s\n' "$new" >"$temporary"
            chmod --reference="$file" "$temporary"
            mv "$temporary" "$file"
            echo "$name $current -> $latest"
          }

          status=0
          for file in "$@"; do
            update_pin "$file" || status=1
          done
          exit "$status"
        '';
      };
    };
}
