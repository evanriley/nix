{
  perSystem =
    { pkgs, lib, ... }:
    {
      packages.scapectl = pkgs.buildGoModule {
        pname = "scapectl";
        version = "0.0.16-unstable-2026-09-18";
        src = pkgs.fetchFromGitHub {
          owner = "charlietran";
          repo = "scapectl";
          rev = "34e2397541e44b03b927334dd4933910f2cd1af7";
          hash = "sha256-qQCNog4ptjevdb5Ghzc03diroskPbB4VSa8G47GGcC8=";
        };
        vendorHash = "sha256-PwY+aPvD62n0XmZSeugKG9M5/o0UFtK4KWxNyQ5YXrs=";
        subPackages = [ "cmd/scapectl" ];
        env.CGO_ENABLED = 0;
        meta = {
          description = "Desktop controller for the Fractal Design Scape headset";
          homepage = "https://github.com/charlietran/scapectl";
          license = lib.licenses.gpl3Only;
          mainProgram = "scapectl";
        };
      };
    };
}
