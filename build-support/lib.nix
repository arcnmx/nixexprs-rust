{ lib ? super // self
, self ? import ../lib { lib = super; } # self.lib
, super ? import <nixpkgs/lib> # nixpkgs.lib
}: let
  inherit (builtins)
    dirOf baseNameOf
    removeAttrs attrNames
  ;
  inherit (lib)
    removeSuffix escapeShellArg concatMapStringsSep concatStringsSep
    mapAttrsToList
    optionals
    isDerivation
    # self.lib
    srcName crateName stripDot
    escapePattern
  ;
  escapeShellArgs = args: lib.escapeShellArgs (map (s: "${s}") args);
in {
  check-rustfmt = {
    rustfmt, cargo, runCommand
  }:
  { src
  , name ? srcName "cargo-fmt-check" src
  , meta ? { name = "cargo fmt"; }
  , nativeBuildInputs ? [ cargo rustfmt ]
  , manifestPath ? "Cargo.toml"
  , config ? null
  , cargoFmtArgs ? [ ]
  , rustfmtArgs ? optionals (config != null) [ "--config-path" (stripDot config) ]
  , ...
  }@args: runCommand name ({
    allowSubstitutes = false;
    inherit meta manifestPath nativeBuildInputs;
    passthru = args.passthru or { } // {
      inherit config cargoFmtArgs rustfmtArgs;
    };
  } // removeAttrs args [ "name" "config" "cargoFmtArgs" "rustfmtArgs" ]) ''
    cargo fmt --check \
      ${escapeShellArgs cargoFmtArgs} \
      --manifest-path "$src/$manifestPath" \
      -- ${escapeShellArgs rustfmtArgs} | tee $out
  '';

  check-generate = { runCommand, diffutils }:
  { name ? srcName "generate-check" expected
  , expected
  , src
  , meta ? { name = "diff ${baseNameOf (toString src)}"; }
  , nativeBuildInputs ? [ diffutils ]
  , ...
  }@args: runCommand name ({
    preferLocalBuild = true;
    inherit nativeBuildInputs meta;
  } // removeAttrs args [ "name" ]) ''
    diff --color=always -uN $src $expected > $out
  '';

  check-contents = { gnugrep, runCommand }:
  { name ? srcName "check-contents" src
  , src
  , patterns ? [ ]
  , nativeBuildInputs ? [ gnugrep ]
  , ...
  }@args: let
    patternMessage = { path, message ? null, ... }@p:
      if message != null then message
      else if p ? docs'rs then "update html_root_url"
      else if p ? cargo'docs then "update package.documentation"
      else "no match";
    mapPattern = { pattern ? null, plain ? null, any ? null, docs'rs ? null, cargo'docs ? null, ... }@p:
      if any != null then concatMapStringsSep " " mapPattern any
      else if docs'rs != null then mapDocsRs docs'rs
      else if cargo'docs != null then mapCargoDocs cargo'docs
      else if pattern != null then ''-e ${escapeShellArg pattern}''
      else if plain != null then mapPattern {
        pattern = escapePattern plain;
      } else throw "Unknown check-contents pattern { ${toString (attrNames p)} }";
    mapDocsRs =
    { version ? null, name ? null
    , baseUrl ? "docs.rs"
    , url ? genDocsUrl { inherit version name baseUrl; } + "/"
    }: mapPattern {
      pattern = escapePattern ''doc(html_root_url = "'' + url + escapePattern ''")'';
    };
    mapCargoDocs =
    { version ? null, name ? null
    , crate ? crateName name
    , baseUrl ? "docs.rs"
    , url ? genDocsUrl { inherit version name baseUrl; } + escapePattern "/${crate}/"
    }: mapPattern {
      pattern = ''documentation = "'' + url + ''"$'';
    };
    genDocsUrl = { version, name, baseUrl ? "docs.rs" }: let
      base =
        if baseUrl == "docs.rs" then escapePattern "https://docs.rs/${name}"
        else if baseUrl == null then ".*"
        else baseUrl;
    in "${base}/${escapePattern version}";
    script = ''
      checkPattern() {
        FNAME="$1"
        MESSAGE="$2"
        shift 2
        echo "grep -E $FNAME $*"
        if ! grep -qE "$FNAME" "$@"; then
          echo "$FNAME: $MESSAGE" >&2
          return 1
        fi
      }

      cd $src
    '' + concatMapStringsSep "\n" ({ path, ... }@pattern: ''
      checkPattern ${escapeShellArg path} ${escapeShellArg (patternMessage pattern)} \
        ${mapPattern pattern}
    '') patterns + ''
      touch $out
    '';
  in runCommand name ({
    inherit nativeBuildInputs;
    passthru = args.passthru or { } // {
      inherit patterns;
    };
  } // removeAttrs args [ "name" "patterns" ]) script;

  wrapSource = { runCommand }: src: if ! isDerivation src then runCommand src.name {
    preferLocalBuild = true;
    inherit src;
    passthru.__toString = self: self.src;
  } ''
    mkdir $out
    ln -s $src/* $out/
  '' else src;

  copyFarm = { runCommand }: name: paths: runCommand name {
    preferLocalBuild = true;
  } (concatMapStringsSep "\n" ({ name, path }: ''
    mkdir -p $out/${escapeShellArg (dirOf name)}
    cp ${path} $out/${escapeShellArg name}
  '') paths);

  adoc2md = { runCommand, asciidoctor, pandoc }:
  { src
  , name ? src.name or (removeSuffix ".adoc" (baseNameOf src) + ".md")
  , attributes ? { }
  , nativeBuildInputs ? [ asciidoctor pandoc ]
  , pandocArgs ? [ "--columns=120" "--wrap=none" ]
  , asciidoctorArgs ? [ ]
  , ...
  }@args: runCommand name ({
    preferLocalBuild = true;
    inherit nativeBuildInputs;
    passthru = args.passthru or { } // {
      inherit attributes pandocArgs asciidoctorArgs;
    };
  } // removeAttrs args [ "name" "attributes" "pandocArgs" "asciidoctorArgs" ]) ''
    asciidoctor $src -b docbook5 -o - ${escapeShellArgs asciidoctorArgs} \
      ${toString (mapAttrsToList (k: v: ''-a "${k}=${v}"'') attributes)} |
      pandoc -f docbook -t gfm ${escapeShellArgs pandocArgs} > $out
  '';

  generateFiles = { writeShellScriptBin }:
  { name ? "generate"
  , paths
  }: writeShellScriptBin name (concatStringsSep "\n" ([ "set -eu" ] ++ mapAttrsToList (path: src:
    ''cp --no-preserve=all ${src} ${escapeShellArg path}''
  ) paths));
}