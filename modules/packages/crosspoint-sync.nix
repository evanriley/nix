{
  perSystem =
    { pkgs, lib, ... }:
    let
      version = "0.1.0-unstable-2026-10-28";
      src = pkgs.fetchFromGitHub {
        owner = "crosspoint-reader";
        repo = "crosspoint-sync";
        rev = "2d5b316541221cf4cac2a6200f8a7b00b5bbe1ef";
        hash = "sha256-Iki+4jQ68T7jBhbivT1Zl4PBa38RBb4CipGDQyNDhMY=";
      };
      web = pkgs.buildNpmPackage {
        pname = "crosspoint-sync-web";
        inherit version;
        src = "${src}/app";
        npmDepsHash = "sha256-w0RsP1dk4MW9NERbkY7whpm6S3tTRhS0enfXrkTJhh8=";
        npmFlags = [ "--ignore-scripts" ];
        buildPhase = ''
          runHook preBuild
          npx vite build
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          cp -r dist $out
          runHook postInstall
        '';
      };
    in
    {
      packages.crosspoint-sync = pkgs.buildNpmPackage {
        pname = "crosspoint-sync";
        inherit version src;
        npmDepsHash = "sha256-kn3etI5vqGfPs+tsIGpNYqWcVJ8je/zBaPiUJKbYQTg=";
        nativeBuildInputs = [ pkgs.makeWrapper ];
        installPhase = ''
          runHook preInstall
          npm prune --omit=dev --no-save
          mkdir -p $out/lib/crosspoint-sync $out/share/crosspoint-sync $out/bin
          cp -r package.json dist node_modules migrations assets extension $out/lib/crosspoint-sync/
          cp -r ${web} $out/share/crosspoint-sync/web
          makeWrapper ${lib.getExe pkgs.nodejs} $out/bin/crosspoint-sync \
            --add-flags $out/lib/crosspoint-sync/dist/index.js \
            --set-default WEB_APP_DIR $out/share/crosspoint-sync/web
          runHook postInstall
        '';
        meta = {
          description = "KOReader-compatible sync server for e-readers with a Hardcover connector";
          homepage = "https://github.com/crosspoint-reader/crosspoint-sync";
          license = lib.licenses.mit;
          mainProgram = "crosspoint-sync";
          platforms = lib.platforms.linux;
        };
      };
    };
}
