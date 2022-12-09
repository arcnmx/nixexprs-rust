{ pkgs ? import <nixpkgs> { } }: let
  pkgs'arm = import pkgs.path {
    localSystem = "x86_64-linux";
    crossSystem = pkgs.lib.systems.examples.arm-embedded // {
      rustc.config = "thumbv7m-none-eabi";
    };
    config.allowUnsupportedSystem = true;
  };
  rust'arm = import ../.. { pkgs = pkgs'arm; };
in {
  cortex-m-quickstart = rust'arm.stable.callPackage ./derivation.nix {
  };
}
