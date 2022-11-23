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
      hasPrefix removePrefix removeSuffix escape escapeShellArg concatMapStringsSep concatStringsSep splitString
      singleton head tail last init flatten elem elemAt filter partition any concatLists concatMap
      genAttrs mapAttrsToList filterAttrs listToAttrs nameValuePair
      optional optionals optionalString optionalAttrs mapNullable
      flip makeOverridable
      cleanSourceWith importTOML
      fakeHash warn
    ;
    inherit (self.lib)
      srcName crateName stripDot
      cratesRegistryUrl
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

      cratesRegistryUrl = "https://github.com/rust-lang/crates.io-index";
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
        detectLockVersion = lock:
          if any (p: p ? checksum) lock.packages or [] then 2
          else if any (hasPrefix "checksum ") (attrNames lock.metadata or {}) then 1
          else null;
        fetchSource = pkg: { fetchurl ? builtins.fetchurl, fetchGit ? builtins.fetchGit, fetchgit ? null, src ? null }: let
          inherit (pkg) source;
        in {
          local = src;
          registry = if source.srcInfo != null then fetchurl {
            inherit (source.srcInfo) name url;
            ${if source.srcInfo.sha256 or null != null then "sha256" else null} = source.srcInfo.sha256;
          } else null;
          git = if fetchgit != null then fetchgit {
            url = source.srcInfo.url;
            rev = source.git.hash;
            ${if pkg.checksum or null != null then "sha256" else null} = pkg.checksum;
          } else fetchGit {
            url = source.srcInfo.url;
            rev = source.git.hash;
            ${if source.git ? rev then "allRefs" else null} = true;
            ${if source.git ? tag || source.git ? branch || hasPrefix "refs/" source.git.ref or "" then "ref" else null} =
              if source.git ? tag then "refs/tags/${source.git.tag}"
              else if source.git ? branch then "refs/heads/${source.git.branch}"
              else source.git.rev;
            ${if pkg.checksum ? submodules then "submodules" else null} = pkg.checksum.submodules;
          };
          path = warn "TODO: path+ source" null;
          directory = warn "TODO: directory+ source" { };
        }.${source.type} or null;
        matchSource = match ''([^+]*)\+(.*)'';
        matchGitUrl = match ''([^?]+)([?&]([^=]*=[^&]*))*#(.*)'';
        parseSource = { source, ... }@pkg: let
          match = matchSource source;
          type = elemAt match 0;
          url = elemAt match 1;
          parsed = {
            inherit type url source;
            __toString = self: self.source;
          } // {
            registry.srcInfo = if source.url == cratesRegistryUrl then {
              name = "crate-${pkg.name}-${pkg.version}.tar.gz";
              url = "https://crates.io/api/v1/crates/${pkg.name}/${pkg.version}/download";
              sha256 = pkg.checksum or null;
            } else warn "unknown registry ${url}" null;
            git = let
              parsed = matchGitUrl url;
              args = tail (init parsed);
            in builtins.trace parsed {
              srcInfo = {
                url = head parsed;
                sha256 = pkg.checksum or null;
              };
              git = {
                hash = last parsed;
              } // listToAttrs (map (p: let
                kv = splitString "=" p;
              in nameValuePair (head kv) (last kv)) args);
            };
            path = { };
            directory = { };
          }.${type} or (warn "unknown source type for ${source}" { });
        in if match == null
          then throw "cannot parse source ${source}"
          else parsed;
        mapDep = lock: name: let
        in {
          name = parsePackageDescriptor name;
          pkg = lock.pkg.${name};
          __toString = self: self.name;
        };
        mapPackage3 = crate: lock: pkg: let
          p = pkg // {
            pname = "${pkg.name}-${pkg.version}";
            descriptor = packageDescriptor pkg;
            checksum = lock.outputHashes.${p.pname} or pkg.checksum or null;
            source = if pkg ? source
              then parseSource pkg
              else {
                type = "local";
                __toString = _: null;
              };
            deps = map (mapDep lock) p.dependencies;
            dependencies = pkg.dependencies or [ ];
            data = pkg;
            src = makeOverridable (fetchSource p) {
              inherit (crate) src;
            };
          };
        in p;
        mapPackage2 = crate: lock: pkg: mapPackage3 crate lock (if pkg ? branch then removeBranch pkg else pkg);
        mapPackage1 = crate: lock: pkg: let
          checksum = lock.metadata."checksum ${packageDescriptor pkg}" or null;
        in mapPackage2 crate lock (pkg // {
          inherit checksum;
        });
        removeBranch = pkg: let
          source = parseSource pkg;
          args = removeAttrs source.git [ "hash" ] // {
            inherit (pkg) branch;
          };
        in assert source.type == "git"; removeAttrs pkg [ "branch" ] // {
          source = "git+${source.srcInfo.url}"
            + optionalString (args != { }) "?${concatStringsSep "&" (mapAttrsToList (k: v: "${k}=${v}") args)}"
            + optionalString (source.git.hash != null) "#${source.git.hash}";
        };
        packageDescriptor = pkg: "${pkg.name} ${pkg.version}" + optionalString (pkg.source or null != null) " (${pkg.source})";
        matchPackageDescriptor = match ''([^ ]*) ([^ ]*)( \(([^)]*)\))?'';
        parsePackageDescriptor = name: let
          match = matchPackageDescriptor name;
        in if match == null then {
          inherit name;
          __toString = self: self.name;
        } else {
          name = elemAt match 0;
          version = elemAt match 1;
          source = mapNullable head (elemAt match 2);
          descriptor = name;
          __toString = self: self.descriptor;
        };
      in {
        path
      , parent ? null
      , globalIgnore ? [ "/.cargo/" "/.github/" ".direnv" ".envrc" "*.nix" "flake.lock" ]
      , cargoLock ? null
      , outputHashes ? { }
      }: let
        paths = if baseNameOf path == "Cargo.toml" then {
          cargoTomlFile = path;
          root = dirOf path;
        } else {
          cargoTomlFile = path + "/Cargo.toml";
          root = path;
        };
        gitignore = paths.root + "/.gitignore";
        globalGitignoreString = concatStringsSep "\n" globalIgnore;
        cargoLockArgs =
          if cargoLock != null then cargoLock
          else if parent != null then parent.cargoLock
          else { lockFile = paths.root + "/Cargo.lock"; };
        cargoToml = importTOML paths.cargoTomlFile;
        crate = cargoToml // {
          inherit (crate.package) name version;
          inherit (paths) root cargoTomlFile;
          inherit parent;
          lock = let
            inherit (crate) lock;
            local = partition (p: p.source.type == "local") lock.packages;
          in {
            version = lock.data.version or (detectLockVersion lock.data);
            contents = cargoLockArgs.lockFileContents or (readFile cargoLockArgs.lockFile);
            data = fromTOML lock.contents;
            pkg = listToAttrs (concatMap (p: [
              (nameValuePair p.name p)
              (nameValuePair p.pname p)
              (nameValuePair p.descriptor p)
            ]) lock.packages);
            packages = map ({
              "3" = mapPackage3;
              "2" = mapPackage2;
              "1" = mapPackage1;
            }.${toString lock.version} or (throw "unsupported Cargo.lock version ${toString lock.version}") crate lock) lock.data.package;
            localPackages = local.right;
            externalPackages = local.wrong;
            gitPackages = filter (p: p.source.type == "git") lock.externalPackages;
            defaultOutputHashes = let
              gitPackages = filter (p: p.data.checksum or null == null) lock.gitPackages;
            in listToAttrs (map (p: nameValuePair p.pname fakeHash) gitPackages);
            outputHashes = cargoLockArgs.outputHashes or lock.defaultOutputHashes // outputHashes;
          };
          cargoLock = cargoLockArgs // {
            inherit (crate.lock) outputHashes;
          };
          cargoVendorDir = { importCargoLock }: importCargoLock crate.cargoLock;
          workspaces = mapAttrs (_: path: importCargo' {
            inherit path globalIgnore outputHashes;
            parent = crate;
          }) crate.workspaceFiles;
          workspaceFiles = genAttrs crate.workspace.members or [ ] (w: crate.root + "/${w}");
          filter = let
            noopFilter = _: _: true;
            defaultFilter = if pathExists (path.root + "/.git")
              then noopFilter
              else path: type: ! hasPrefix "." (baseNameOf path);
            baseExcludes = [ "${toString crate.root}/target" "${toString crate.root}/.git" ];
            baseExclude = path: type: type != "directory" || ! (
              elem path baseExcludes || isSubpackage path
            );
            baseIncludes = [ "${toString crate.root}/Cargo.toml" "${toString crate.root}/Cargo.lock" ]
              ++ optional (crate ? package.license-file) crate.package.license-file
              ++ optional (crate ? package.readme) crate.package.readme;
            baseInclude = path: type: type == "regular" && (
              elem path baseIncludes
            );
            dirIncludes = map (r: toString (crate.root + "/${r}")) (concatMap (rule: superrule crate.root (dirOf rule)) crate.package.include or [ ]);
            dirInclude = path: type: type == "directory" && elem path dirIncludes;
            include =
              if crate ? package.include then nix-gitignore.gitignoreFilterPure noopFilter (
                negateInclude crate.root crate.package.include
              ) crate.root else if pathExists gitignore then nix-gitignore.gitignoreFilterPure noopFilter (
                globalGitignoreString + "\n" + readFile gitignore
              ) crate.root else nix-gitignore.gitignoreFilterPure defaultFilter (
                globalGitignoreString
              ) crate.root;
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
