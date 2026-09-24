{
  # A script from this repository as a package: shebang patched to the store
  # and its runtime tools prepended to PATH.
  flake.lib.mkScript =
    pkgs:
    {
      name,
      src,
      runtimeInputs ? [ ],
    }:
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        buildInputs = [ pkgs.python3 ];
        meta.mainProgram = name;
      }
      ''
        install -Dm755 ${src} $out/bin/${name}
        patchShebangs $out/bin
        wrapProgram $out/bin/${name} --prefix PATH : ${pkgs.lib.makeBinPath runtimeInputs}
      '';
}
