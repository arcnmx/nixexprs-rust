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
    forSystems = genAttrs self.lib.systems;
    impure = builtins ? currentSystem;
    inherit (builtins)
      mapAttrs removeAttrs
    ;
    inherit (nixlib)
      elem filter
      genAttrs filterAttrs
      optionalAttrs
      flip
    ;
  in {
    legacyPackages = forSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      packages = self.packages.${system};
      legacyPackages = self.legacyPackages.${system};
      inherit (legacyPackages) builders;
    in (pkgs.extend self.overlays.rustChannel).rustChannel // {
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

    overlays = let
      fixFlakeOverlay = overlay:
        final: prev: (import overlay) final prev;
    in {
      rustChannel = fixFlakeOverlay ./overlay.nix;
      lib = fixFlakeOverlay ./lib/overlay.nix;
      default = self.overlays.rustChannel;
    };

    devShells = forSystems (system: let
      legacyPackages = self.legacyPackages.${system};
      filterBroken = filterAttrs (_: c: c.toolsAvailable);
      channels = {
        inherit (legacyPackages) latest stable unstable;
      } // optionalAttrs impure {
        inherit (legacyPackages) beta nightly;
      } // filterBroken legacyPackages.releases;
      channelShells = mapAttrs (_: c: c.mkShell { }) channels;
    in {
      default = self.devShells.${system}.latest;
    } // channelShells);

    builders = import ./build-support/lib.nix {
      self = self.lib;
      super = nixlib;
    };

    lib = self.overlays.lib self.lib nixlib // {
      systems = filter (s: ! elem s unsupportedSystems)
        nixpkgs.lib.systems.flakeExposed or nixpkgs.lib.systems.supported.hydra;

      nix-gitignore = let
        gitignore = import (nixpkgs + "/pkgs/build-support/nix-gitignore") {
          inherit (nixpkgs) lib;
          runCommand = throw "runCommand";
        };
      in removeAttrs gitignore [
        # these use runCommand
        "withRecursiveGitignoreFile"
        "compileRecursiveGitignore"
        "gitignoreFilterRecursiveSource"
      ];
    };

    flakes = {
      config = rec {
        name = "rust";
        packages.namespace = [ name ];
      };
      systems = forSystems nixpkgs.lib.id;
    };
  };
}
