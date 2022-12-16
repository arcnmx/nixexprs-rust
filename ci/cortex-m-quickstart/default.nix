{ pkgs ? import <nixpkgs> { } }: let
  pkgs'arm = import pkgs.path {
    localSystem = "x86_64-linux";
    crossSystem = pkgs.lib.systems.examples.arm-embedded // {
      rustc = rec {
        config = "thumbv7m-none-eabi";
        platform = {
          # optional, for testing with upstream pkgs.buildRustPackage
          llvm-target = config;
          arch = "thumbv7m";
          target-pointer-width = 32;
          target-c-int-width = 32;
          os = "none";
          linker-flavor = "ld";
          panic-strategy = "abort";
        };
      };
    };
    config.allowUnsupportedSystem = true;
  };
  rust'arm = import ../.. { pkgs = pkgs'arm; };
in {
  cortex-m-quickstart = rust'arm.stable.callPackage ./derivation.nix {
  };
}
