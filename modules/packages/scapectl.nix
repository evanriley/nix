{
  perSystem =
    { pkgs, lib, ... }:
    {
      packages.scapectl = pkgs.buildGoModule {
        pname = "scapectl";
        version = "0.0.19-unstable-2026-11-13";
        src = pkgs.fetchFromGitHub {
          owner = "charlietran";
          repo = "scapectl";
          rev = "331cadd3bdbe69898da6b203625320df171e321c";
          hash = "sha256-WrqAtvytz+HBNK/mLgmzcd91bGj7b5Ny/mrZCtRgMgI=";
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
