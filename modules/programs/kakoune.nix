{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      inherit (inputs) helix;

      # Kakoune filetype -> Helix grammar name.
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

      helixGrammars = (fromTOML (builtins.readFile "${helix}/languages.toml")).grammar;
      grammarSource =
        name:
        (lib.findFirst (
          grammar: grammar.name == name
        ) (throw "helix pins no tree-sitter grammar named ${name}") helixGrammars).source;

      buildGrammar =
        name:
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

      # Every default language is listed without remove_default_highlighter,
      # otherwise languages without a grammar here lose all highlighting.
      wanted = builtins.toJSON {
        grammar = lib.mapAttrs' (
          _: grammar:
          lib.nameValuePair grammar { source.local.path = "${buildGrammar grammar}/${grammar}.so"; }
        ) treeSitterLanguages;
        language = lib.mapAttrs (_: grammar: {
          inherit grammar;
          queries.source.local.path = "${helix}/runtime/queries/${grammar}";
          remove_default_highlighter = true;
          filetype_hook = true;
        }) treeSitterLanguages;
      };

      treeSitterConfig =
        pkgs.runCommand "kak-tree-sitter-config.toml"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.remarshal
            ];
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

      # Layout expected by simple-completion-language-server:
      # <config dir>/external-snippets/<git url path>.
      snippetSources = (pkgs.formats.toml { }).generate "external-snippets.toml" {
        sources = [
          {
            name = "friendly-snippets";
            git = "https://github.com/rafamadriz/friendly-snippets";
            paths = [
              {
                scope = [ "python" ];
                path = "snippets/python";
              }
              {
                scope = [ "rust" ];
                path = "snippets/rust/rust.json";
              }
              {
                scope = [ "zig" ];
                path = "snippets/zig.json";
              }
              {
                scope = [ "gleam" ];
                path = "snippets/gleam.json";
              }
            ];
          }
        ];
      };

      # kakoune-lsp sends full-document changes and may skip didOpen for the
      # second server; unpatched, snippet completion never sees buffer edits.
      snippetServer = pkgs.simple-completion-language-server.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./_kakoune/scls-full-document-sync.patch ];
      });

      plugin =
        name: src:
        pkgs.runCommand "kak-plugin-${name}" { } ''
          mkdir -p $out/share/kak/autoload/plugins
          cp -r ${src} $out/share/kak/autoload/plugins/${name}
        '';

      # share/kak/bin is appended to PATH by the wrapper, so project tools win.
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
    in
    {
      packages.kakoune = pkgs.wrapKakoune pkgs.kakoune-unwrapped {
        plugins = [
          tools
          (plugin "auto-pairs" inputs.kak-auto-pairs)
          (plugin "kakoune-surround" inputs.kak-surround)
          (plugin "kak-rainbow" inputs.kak-rainbow)
        ];
      };
    };

  flake.modules.homeManager.kakoune =
    { pkgs, ... }:
    {
      dotfiles.config = [ "kak" ];
      home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.kakoune ];
    };
}
