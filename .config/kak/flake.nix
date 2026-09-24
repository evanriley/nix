{
  description = "Kakoune with the editor-private tools this configuration uses";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Tree-sitter grammar revisions and the queries written against them.
    helix = {
      url = "github:helix-editor/helix";
      flake = false;
    };

    auto-pairs = {
      url = "github:alexherbo2/auto-pairs.kak";
      flake = false;
    };
    kakoune-surround = {
      url = "github:h-youhei/kakoune-surround";
      flake = false;
    };
    kak-rainbow = {
      url = "github:Bodhizafa/kak-rainbow";
      flake = false;
    };
    friendly-snippets = {
      url = "github:rafamadriz/friendly-snippets";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, helix, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = lib.genAttrs supportedSystems;

      # Kakoune filetype -> tree-sitter grammar name used by Helix.
      treeSitterLanguages = {
        clojure = "clojure";
        zig = "zig";
        gleam = "gleam";
        rust = "rust";
        python = "python";
        sh = "bash";
        fish = "fish";
        toml = "toml";
        json = "json";
        yaml = "yaml";
        nix = "nix";
        c = "c";
        ocaml = "ocaml";
      };

      helixGrammars = (builtins.fromTOML (builtins.readFile "${helix}/languages.toml")).grammar;
      grammarSource = name:
        (lib.findFirst (grammar: grammar.name == name)
          (throw "helix pins no tree-sitter grammar named ${name}")
          helixGrammars).source;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          buildGrammar = name:
            let
              source = grammarSource name;
            in
            pkgs.stdenv.mkDerivation {
              pname = "tree-sitter-grammar-${name}";
              version = builtins.substring 0 12 source.rev;
              src = builtins.fetchTree {
                type = "git";
                url = source.git;
                inherit (source) rev;
                shallow = true;
              };
              dontConfigure = true;
              buildPhase = ''
                runHook preBuild
                cd ${source.subpath or "."}/src
                objects=parser.o
                $CC -O2 -fPIC -I. -c parser.c
                if [ -e scanner.c ]; then $CC -O2 -fPIC -I. -c scanner.c; objects="$objects scanner.o"; fi
                if [ -e scanner.cc ]; then $CXX -O2 -fPIC -I. -c scanner.cc; objects="$objects scanner.o"; fi
                $CXX -shared -o parser.so $objects
                runHook postBuild
              '';
              installPhase = ''
                install -Dm755 parser.so $out/${name}.so
              '';
            };

          # kak-tree-sitter merges this over its built-in defaults, and removes
          # Kakoune's own highlighter for every language it knows. Languages we
          # have no grammar for keep Kakoune's highlighter.
          wanted = builtins.toJSON {
            grammar = lib.mapAttrs' (_: grammar:
              lib.nameValuePair grammar { source.local.path = "${buildGrammar grammar}/${grammar}.so"; })
              treeSitterLanguages;
            language = lib.mapAttrs (_: grammar: {
              inherit grammar;
              queries.source.local.path = "${helix}/runtime/queries/${grammar}";
              remove_default_highlighter = true;
              filetype_hook = true;
            }) treeSitterLanguages;
          };

          treeSitterConfig = pkgs.runCommand "kak-tree-sitter-config.toml"
            {
              nativeBuildInputs = [ pkgs.python3 pkgs.remarshal ];
              defaults = "${pkgs.kak-tree-sitter-unwrapped.src}/kak-tree-sitter-config/default-config.toml";
              inherit wanted;
              passAsFile = [ "wanted" ];
            }
            ''
              python3 - > config.json <<'PY'
              import json, os, tomllib
              with open(os.environ['defaults'], 'rb') as stream:
                  defaults = tomllib.load(stream)
              with open(os.environ['wantedPath']) as stream:
                  config = json.load(stream)
              for name in defaults.get('language', {}):
                  config['language'].setdefault(name, {
                      'remove_default_highlighter': False,
                      'filetype_hook': False,
                  })
              json.dump(config, os.sys.stdout)
              PY
              json2toml config.json $out
            '';

          # simple-completion-language-server reads collections from
          # <config dir>/external-snippets/<git url path>; build that layout in the store.
          snippetSources = (pkgs.formats.toml { }).generate "external-snippets.toml" {
            sources = [{
              name = "friendly-snippets";
              git = "https://github.com/rafamadriz/friendly-snippets";
              paths = [
                { scope = [ "python" ]; path = "snippets/python"; }
                { scope = [ "rust" ]; path = "snippets/rust/rust.json"; }
                { scope = [ "zig" ]; path = "snippets/zig.json"; }
                { scope = [ "gleam" ]; path = "snippets/gleam.json"; }
              ];
            }];
          };

          # kakoune-lsp sends whole documents on change and may skip didOpen for a server
          # that initializes second; the server only understood ranged edits of opened
          # documents, so its copy of the buffer never updated and completion failed.
          snippetServer = pkgs.simple-completion-language-server.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./nix/scls-full-document-sync.patch ];
          });

          plugin = name: src: pkgs.runCommand "kak-plugin-${name}" { } ''
            mkdir -p $out/share/kak/autoload/plugins
            cp -r ${src} $out/share/kak/autoload/plugins/${name}
          '';

          # Binaries only Kakoune and its children see (share/kak/bin is
          # appended to PATH by the Kakoune wrapper, so project tools win).
          tools = pkgs.runCommand "kakoune-tools" { } ''
            mkdir -p $out/share/kak/bin $out/share/kak/autoload/plugins $out/share/kak/tree-sitter
            for tool in ${pkgs.kakoune-lsp}/bin/kak-lsp \
                        ${pkgs.kak-tree-sitter}/bin/kak-tree-sitter \
                        ${pkgs.kak-tree-sitter}/bin/ktsctl \
                        ${snippetServer}/bin/simple-completion-language-server \
                        ${pkgs.parinfer-rust}/bin/parinfer-rust; do
              ln -s "$tool" $out/share/kak/bin/
            done
            ln -s ${pkgs.parinfer-rust}/share/kak/autoload/plugins/parinfer.kak $out/share/kak/autoload/plugins/
            ln -s ${treeSitterConfig} $out/share/kak/tree-sitter/config.toml
            mkdir -p $out/share/kak/scls/external-snippets/github.com/rafamadriz
            ln -s ${snippetSources} $out/share/kak/scls/external-snippets.toml
            ln -s ${inputs.friendly-snippets} $out/share/kak/scls/external-snippets/github.com/rafamadriz/friendly-snippets
          '';

          kakoune = pkgs.wrapKakoune pkgs.kakoune-unwrapped {
            plugins = [
              tools
              (plugin "auto-pairs" inputs.auto-pairs)
              (plugin "kakoune-surround" inputs.kakoune-surround)
              (plugin "kak-rainbow" inputs.kak-rainbow)
            ];
          };
        in
        {
          inherit kakoune treeSitterConfig;
          default = kakoune;
        }
      );
    };
}
