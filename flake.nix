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
    systems = nixlib.filter (s: ! builtins.elem s unsupportedSystems) nixlib.systems.flakeExposed or nixlib.systems.supported.hydra;
    forSystems = nixlib.genAttrs systems;
    impure = builtins ? currentSystem;
  in {
    legacyPackages = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      packages = self.packages.${system};
      legacyPackages = self.legacyPackages.${system};
      inherit (legacyPackages) builders;
    in import ./default.nix { inherit pkgs; } // {
      builders = nixlib.mapAttrs (_: nixlib.flip pkgs.callPackage { }) self.builders // {
        check-rustfmt-unstable = builders.check-rustfmt.override {
          rustfmt = packages.rustfmt-unstable;
        };
      };
    });

    packages = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (self.legacyPackages.${system}) latest;
      filterBroken = nixlib.filterAttrs (_: p: p.meta.available);
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
      filterBroken = nixlib.filterAttrs (_: c: c.toolsAvailable);
      channels = {
        inherit (legacyPackages) latest;
      } // nixlib.optionalAttrs impure {
        inherit (legacyPackages) stable beta nightly;
      } // filterBroken legacyPackages.releases;
      channelShells = builtins.mapAttrs (_: c: c.mkShell { }) channels;
    in {
      default = self.devShells.${system}.latest;
    } // channelShells);

    builders = {
      check-rustfmt = {
        rustfmt, cargo, runCommand
      }:
      { src
      , name ? self.lib.srcName "cargo-fmt-check" src
      , meta ? { name = "cargo fmt"; }
      , nativeBuildInputs ? [ cargo rustfmt ]
      , manifestPath ? "Cargo.toml"
      , cargoFmtArgs ? [ ]
      , rustfmtArgs ? [ ]
      , ...
      }@attrs: runCommand name ({
        allowSubstitutes = false;
        inherit meta manifestPath nativeBuildInputs;
      } // builtins.removeAttrs attrs [ "name" "cargoFmtArgs" "rustfmtArgs" ]) ''
        cargo fmt --check \
          ${nixlib.escapeShellArgs cargoFmtArgs} \
          --manifest-path "$src/$manifestPath" \
          -- ${nixlib.escapeShellArgs rustfmtArgs} | tee $out
      '';

      check-generate = { runCommand, diffutils }:
      { name ? self.lib.srcName "generate-check" expected
      , expected
      , src
      , meta ? { name = "diff ${builtins.baseNameOf (toString src)}"; }
      , nativeBuildInputs ? [ diffutils ]
      , ...
      }@args: runCommand name ({
        preferLocalBuild = true;
        inherit nativeBuildInputs;
        inherit meta;
      } // args) ''
        diff --color=always -uN $src $expected > $out
      '';

      linkSources =
      { linkFarm
      , copyFarm ? self.legacyPackages.${system}.builders.copyFarm, system ? builtins.currentSystem
      , runCommand
      }:
      { name ? (nixlib.importTOML (path + "/Cargo.toml")).package.name + "-source"
      , path
      , outPath ? if builtins ? storePath then builtins.storePath path else path
      , srcs
      , sha256 ? null
      , isStoreCopy ? nixlib.isStorePath (toString path)
      , useBuiltin ? builtins ? currentSystem || sha256 != null || isStoreCopy
      }: let
        root = path;
        paths = map (src: rec {
          name = nixlib.removePrefix (toString root + "/") (toString src);
          path = if isStoreCopy then "${outPath}/${name}" else src;
        }) srcs;
        paths'path = map ({ path, ... }: toString path) paths;
        filtered = builtins.path {
          inherit path name;
          filter = path: type: if type == "directory"
          then nixlib.findFirst (nixlib.hasPrefix path) null paths'path != null
          else builtins.elem (toString path) paths'path;
          ${if sha256 != null then "sha256" else null} = sha256;
        };
      in if useBuiltin then runCommand name {
        preferLocalBuild = true;
        src = filtered;
        passthru.__toString = self: self.src;
      } ''
        mkdir $out
        ln -s $src/* $out/
       '' else (if isStoreCopy then linkFarm else copyFarm) name paths;

      copyFarm = { runCommand }: name: paths: runCommand name {
        preferLocalBuild = true;
      } (nixlib.concatMapStringsSep "\n" ({ name, path }: ''
        mkdir -p $out/${nixlib.escapeShellArg (builtins.dirOf name)}
        cp ${path} $out/${nixlib.escapeShellArg name}
      '') paths);

      adoc2md = { runCommand, asciidoctor, pandoc }:
      { src
      , name ? src.name or (nixlib.removeSuffix ".adoc" (builtins.baseNameOf src) + ".md")
      , attributes ? { }
      , nativeBuildInputs ? [ asciidoctor pandoc ]
      , pandocArgs ? [ "--columns=120" "--wrap=none" ]
      , asciidoctorArgs ? [ ]
      , ...
      }@attrs: runCommand name ({
        preferLocalBuild = true;
        inherit nativeBuildInputs;
      } // builtins.removeAttrs attrs [ "name" "attributes" "pandocArgs" "asciidoctorArgs" ]) ''
        asciidoctor $src -b docbook5 -o - ${nixlib.escapeShellArgs asciidoctorArgs} \
          ${toString (nixlib.mapAttrsToList (k: v: ''-a "${k}=${v}"'') attributes)} |
          pandoc -f docbook -t gfm ${nixlib.escapeShellArgs pandocArgs} > $out
      '';

      generateFiles = { writeShellScriptBin }:
      { name ? "generate"
      , paths
      }: writeShellScriptBin name (nixlib.concatStringsSep "\n" ([ "set -eu" ] ++ nixlib.mapAttrsToList (path: src:
        ''cp --no-preserve=all ${src} ${nixlib.escapeShellArg path}''
      ) paths));
    };

    lib = {
      srcName = prefix: src: let
        pname = src.pname or (builtins.parseDrvName src.name).name;
      in prefix + nixlib.optionalString (pname != "source") "-${pname}";
    };

    flakes.config = rec {
      name = "rust";
      packages.namespace = [ name ];
    };
  };
}
