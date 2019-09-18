{ pkgs, lib, self, ... }: lib.mapAttrs (_: lib.flip pkgs.callPackage { }) {
  mkShell = { lib, buildPackages, mkShell, rustPlatform }: {
    rustfmtDist ? false # use rustfmt from the binary channel rather than from nixpkgs
  , cargoCommands ? [] # e.g. [ "bloat" "binutils" "fmt" "clippy" etc ]
  , rustTools ? [] # [ "llvm-tools" "rust-analyzer" "rls" "xargo" "gdb" "lldb" etc ]
  # TODO: enableRustLld? better to put that in the channel config though...
  , ...}@args: with lib; let
    env = removeAttrs args [
      "rustfmtDist"
      "cargoCommands" "rustTools"
      "nativeBuildInputs"
    ];
    mapCargo = c: {
        "fmt" = if rustfmtDist then rustPlatform.rustfmt else buildPackages.rustfmt;
        "binutils" = rustPlatform.cargo-binutils;
        "miri" = rustPlatform.miri;
        "clippy" = rustPlatform.clippy;
      }.${c} or buildPackages."cargo-${c}";
    mapTool = c: {
      "rust-analyzer" = buildPackages.rust-analyzer;
    }.${c} or rustPlatform.${c};
  in mkShell ({
    nativeBuildInputs = args.nativeBuildInputs or []
      ++ [ rustPlatform.rustc rustPlatform.cargo ]
      ++ map mapTool rustTools
      ++ map mapCargo cargoCommands;
  } // env);
}
