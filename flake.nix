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
    legacyPackages = forSystems (system: import ./default.nix {
      pkgs = nixpkgs.legacyPackages.${system};
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

    flakes.config = rec {
      name = "rust";
      packages.namespace = [ name ];
    };
  };
}
