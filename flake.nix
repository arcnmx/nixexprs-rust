{
  inputs = {
    nixpkgs = {
    };
  };
  outputs = { nixpkgs, self, ... }: let
    nixlib = nixpkgs.lib;
    unsupportedSystems = [
      "mipsel-linux" # no nixpkgs bootstrap error: attribute 'busybox' missing
      "armv5tel-linux" # error: missing bootstrap url for platform armv5te-unknown-linux-gnueabi
    ];
    systems = filter (s: ! elem s unsupportedSystems) nixlib.systems.flakeExposed or nixlib.systems.supported.hydra;
    forSystems = genAttrs systems;
    impure = builtins ? currentSystem;
    inherit (builtins)
      parseDrvName replaceStrings match
      dirOf baseNameOf pathExists readFile readDir
      mapAttrs removeAttrs attrNames attrValues
      isAttrs isPath isString
    ;
    inherit (nixlib)
      hasPrefix removePrefix removeSuffix escape concatMapStringsSep concatStringsSep
      singleton flatten elem filter any concatLists concatMap
      genAttrs mapAttrsToList filterAttrs
      optional optionals optionalString optionalAttrs flip
      escapeShellArg
      cleanSourceWith importTOML
    ;
    inherit (self.lib)
      srcName crateName stripDot
      escapePattern
    ;
    escapeShellArgs = args: nixlib.escapeShellArgs (map (s: "${s}") args);
  in {
    legacyPackages = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      packages = self.packages.${system};
      legacyPackages = self.legacyPackages.${system};
      inherit (legacyPackages) builders;
    in import ./default.nix { inherit pkgs; } // {
      builders = mapAttrs (_: flip pkgs.callPackage { }) self.builders // {
        check-rustfmt-unstable = builders.check-rustfmt.override {
          rustfmt = packages.rustfmt-unstable;
        };
      };
    });

    packages = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (self.legacyPackages.${system}) latest;
      filterBroken = filterAttrs (_: p: p.meta.available);
    in {
      rustfmt-unstable = pkgs.rustfmt.override {
        asNightly = true;
      };
      inherit (latest)
        rustfmt rust-sysroot
        llvm-tools bintools cargo-binutils
        cargo-unwrapped rustc-unwrapped
        cargo rustc rust-src;
      inherit (latest.tools) rust-std rustc-dev;
    } // filterBroken {
      inherit (latest)
        clippy rls rust-analyzer rust-analyzer-unwrapped
        gdb lldb miri;
    });

    overlays.default = import ./overlay.nix;

    devShells = forSystems (system: let
      legacyPackages = self.legacyPackages.${system};
      filterBroken = filterAttrs (_: c: c.toolsAvailable);
      channels = {
        inherit (legacyPackages) latest stable;
      } // optionalAttrs impure {
        inherit (legacyPackages) beta nightly;
      } // filterBroken legacyPackages.releases;
      channelShells = mapAttrs (_: c: c.mkShell { }) channels;
    in {
      default = self.devShells.${system}.latest;
    } // channelShells);

    builders = {
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

      wrapSource = { runCommand }: src: runCommand src.name {
        preferLocalBuild = true;
        inherit src;
        passthru.__toString = self: self.src;
      } ''
        mkdir $out
        ln -s $src/* $out/
      '';

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
    };

    lib = let
      inherit (self.lib)
        importCargo'
        flattenFiles filterFiles filterFilesRecursive
        nix-gitignore
      ;
    in {
      srcName = prefix: src: let
        pname = src.pname or (parseDrvName src.name).name;
      in prefix + optionalString (pname != "source") "-${pname}";

      stripDot = path: let
        name = baseNameOf path;
      in if isPath path && hasPrefix "." name then builtins.path {
        name = removePrefix "." name;
        inherit path;
        recursive = false;
      } else path;
      crateName = replaceStrings [ "-" ] [ "_" ];

      escapePattern = escape (["." "*" "[" "]" "(" ")" "^" "$"]);

      ghPages = { owner, repo, path ? null }: "https://${owner}.github.io/${repo}"
        + optionalString (path != null) "/${path}";

      nix-gitignore = import (nixpkgs + "/pkgs/build-support/nix-gitignore") {
        inherit (nixpkgs) lib;
        runCommand = throw "runCommand";
      };

      importCargo' = let
        negateRule = rule: if hasPrefix "!" rule then removePrefix "!" rule else "!${rule}";
        superrule = root: rule: let
          negated = if hasPrefix "!" rule then "!" else "";
          rule' = removePrefix "!" rule;
        in if elem rule' [ "/" "." root ] then [ ]
          else singleton rule ++ superrule root (negated + (dirOf rule'));
        negateInclude = root: rules: let
          rules' = concatMap (superrule root) rules;
        in concatStringsSep "\n" (singleton "/**" ++ map negateRule rules');
        isSubpackage = path: pathExists (path + "/Cargo.toml");
      in {
        path
      , parent ? null
      }: let
        paths = if baseNameOf path == "Cargo.toml" then {
          cargoTomlFile = path;
          root = dirOf path;
        } else {
          cargoTomlFile = path + "/Cargo.toml";
          root = path;
        };
        gitignore = paths.root + "/.gitignore";
        cargoLockFile = if parent != null then parent.cargoLockFile else paths.root + "/Cargo.lock";
        cargoToml = importTOML paths.cargoTomlFile;
        crate = cargoToml // {
          inherit (paths) root cargoTomlFile;
          inherit parent cargoLockFile;
          workspaces = mapAttrs (_: path: importCargo' {
            inherit path;
            parent = crate;
          }) crate.workspaceFiles;
          workspaceFiles = genAttrs crate.workspace.members or [ ] (w: crate.root + "/${w}");
          filter = let
            noopFilter = _: _: true;
            baseExcludes = [ "${toString crate.root}/target" ];
            baseExclude = path: type: type != "directory" || ! (
              elem (toString path) baseExcludes || baseNameOf path == ".git" || isSubpackage path
            );
            baseIncludes = [ "${toString crate.root}/Cargo.toml" "${toString crate.root}/Cargo.lock" ]
              ++ optional (crate ? package.license-file) crate.package.license-file
              ++ optional (crate ? package.readme) crate.package.readme;
            baseInclude = path: type: type == "regular" && (
              elem (toString path) baseIncludes
            );
            dirIncludes = map (r: toString (crate.root + "/${r}")) (concatMap (rule: superrule crate.root (dirOf rule)) crate.package.include or [ ]);
            dirInclude = path: type: type == "directory" && elem path dirIncludes;
            include =
              if crate ? package.include then
                nix-gitignore.gitignoreFilterPure noopFilter (negateInclude crate.root crate.package.include) crate.root
              else if pathExists gitignore then
                nix-gitignore.gitignoreFilterPure noopFilter (readFile gitignore) crate.root
              else path: type: ! hasPrefix "." (baseNameOf path);
            exclude =
              if crate ? package.exclude then
                nix-gitignore.gitignoreFilterPure baseExclude crate.package.exclude crate.root
              else baseExclude;
            crates = singleton crate ++ attrValues crate.workspaces;
          in {
            include = path: type: baseInclude path type || include path type;
            inherit exclude dirInclude;
            workspace = path: type: any (w: hasPrefix (toString w.root) path && (
              path == toString w.root || w.filter path type
            )) crates;
            __functor = self: path: type: (self.exclude path type || self.dirInclude path type) && self.include path type;
          };
          pkgSrcs = flattenFiles crate.root (filterFilesRecursive crate.root crate.filter);
          srcs = crate.pkgSrcs ++ concatLists (mapAttrsToList (_: c: c.pkgSrcs) crate.workspaces);
          workspaceSrcs = flattenFiles crate.root (filterFilesRecursive crate.root crate.filter.workspace);
          pkgSrc = cleanSourceWith {
            src = crate.root;
            inherit (crate) filter;
            name = crate.package.name + "-pkgsource-${crate.package.version}";
          };
          src = cleanSourceWith {
            src = crate.root;
            filter = crate.filter.workspace;
            name = crate.package.name + "-source-${crate.package.version}";
          };
          outPath = paths.cargoTomlFile;
        };
      in crate;

      importCargo = args: if isPath args || isString args then importCargo' {
        path = args;
      } else importCargo' args;

      filterFiles = root: filter: filterAttrs (name: type: filter (toString root + "/${name}") type) (readDir root);
      filterFilesRecursive = root: filter: mapAttrs (name: type: if type == "directory"
        then filterFilesRecursive (root + "/${name}") filter
        else type
      ) (filterFiles root filter);
      flattenFiles = root: files: flatten (mapAttrsToList (name: typeOrDir: let
        path = root + "/${name}";
      in if isAttrs typeOrDir
        then flattenFiles path typeOrDir
        else singleton path
      ) files);
    };

    flakes.config = rec {
      name = "rust";
      packages.namespace = [ name ];
    };
  };
}
