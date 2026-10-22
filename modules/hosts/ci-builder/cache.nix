{ config, ... }:
let
  inherit (config.meta) secrets;
  store = "s3://ci-builder-512119-maybe-ci-cache?endpoint=storage.googleapis.com&region=auto&compression=zstd";
  publicKey = "maybe-ci-1:OL1ilQ7u5eRHlhqJfRmrodIRZ4Bp7kk/i7gekhB1Fh4=";
  mainAgent = "buildkite-agent-main";
in
{
  flake.modules.nixos.ci-builder-cache =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.ciBuilder;
      upload = pkgs.writeShellApplication {
        name = "ci-cache-upload";
        runtimeInputs = [
          config.nix.package
          pkgs.jq
        ];
        text = ''
          key=${cfg.runtimeDir}/cache-signing-key
          credentials=${cfg.runtimeDir}/cache-credentials
          if [ ! -s "$key" ] || [ ! -s "$credentials" ]; then
            exit 0
          fi
          if ! features=$(nix derivation show "$DRV_PATH" | jq -r '
            (.derivations // .)[] | (.env.requiredSystemFeatures // "" | split(" "))
              + (.env.__json // "{}" | fromjson | .requiredSystemFeatures // [])
              + (.structuredAttrs.requiredSystemFeatures // []) | join(" ")'); then
            echo "reading the system features of $DRV_PATH failed; not uploading its outputs to the CI cache" >&2
            exit 0
          fi
          case " $features " in
            *" big-parallel "*) ;;
            *) exit 0 ;;
          esac
          read -ra outputs <<<"$OUT_PATHS"
          # GCS rejects the AWS SDK's default request checksums with "Invalid argument".
          if ! AWS_SHARED_CREDENTIALS_FILE=$credentials AWS_EC2_METADATA_DISABLED=true \
            AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
            nix copy --to "${cfg.cacheStore}&secret-key=$key" "''${outputs[@]}"; then
            echo "uploading ''${outputs[*]} to the CI cache failed; publish builds them on blaziken instead" >&2
          fi
        '';
      };
    in
    {
      options.ciBuilder.cacheStore = lib.mkOption {
        type = lib.types.str;
        default = store;
        description = "Binary cache, with at least one query parameter, that receives the closures of big-parallel outputs built here.";
      };

      config.nix.settings.post-build-hook = lib.getExe upload;
    };

  flake.modules.nixos.blaziken =
    { config, ... }:
    {
      nix.settings = {
        extra-substituters = [ "${store}&priority=50" ];
        extra-trusted-public-keys = [ publicKey ];
        fallback = true;
      };

      # Lix's socket runs each connection in a nix-daemon@ instance; nix-daemon.service never starts.
      systemd.services."nix-daemon@".environment.AWS_SHARED_CREDENTIALS_FILE =
        config.age.secrets.ci-cache-reader.path;

      systemd.services.ci-spot-poller.environment = {
        CI_CACHE_CREDENTIALS_PATH = config.age.secrets.ci-cache-writer.path;
        CI_CACHE_SIGNING_KEY_PATH = config.age.secrets.ci-cache-signing-key.path;
      };

      age.secrets = {
        ci-cache-reader.file = secrets + "/blaziken/ci-cache-reader.age";
        ci-cache-writer = {
          file = secrets + "/blaziken/ci-cache-writer.age";
          owner = mainAgent;
        };
        ci-cache-signing-key = {
          file = secrets + "/blaziken/ci-cache-signing-key.age";
          owner = mainAgent;
        };
      };
    };
}
