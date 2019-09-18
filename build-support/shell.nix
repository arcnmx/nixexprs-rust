{ pkgs, lib, self, ... }: lib.mapAttrs (_: lib.flip pkgs.callPackage { }) {
  mkShell = { lib, buildPackages, mkShell, rustPlatform }: {
    enableRls ? false
  , enableRustAnalyzer ? false
  , enableLlvmTools ? false
  , enableLldb ? false
  , rustfmtDist ? false # use rustfmt from the binary channel rather than from nixpkgs
  , cargoCommands ? [] # e.g. [ "bloat" "binutils" "fmt" "clippy" etc ]
  # TODO: enableRustLld? better to put that in the channel config though...
  , ...}@args: with lib;
  assert enableRustAnalyzer -> buildPackages.rust-analyzer != null; let
    env = removeAttrs args [
      "enableRls" "enableRustAnalyzer" "enableLlvmTools" "cargoCommands"
      "nativeBuildInputs"
    ];
    mapCargo = c: {
        "fmt" = if rustfmtDist then rustPlatform.rustfmt else buildPackages.rustfmt;
        "binutils" = rustPlatform.cargo-binutils;
        "xargo" = rustPlatform.xargo;
        "miri" = rustPlatform.miri;
        "clippy" = rustPlatform.clippy;
      }.${c} or buildPackages."cargo-${c}";
    cargoExtras = map mapCargo cargoCommands;
  in mkShell ({
    nativeBuildInputs = args.nativeBuildInputs or []
      ++ [ rustPlatform.rustc rustPlatform.cargo ]
      ++ optional enableRls rustPlatform.rls
      ++ optional enableRustAnalyzer buildPackages.rust-analyzer
      ++ optional enableLldb rustPlatform.lldb
      ++ optional enableLlvmTools rustPlatform.llvm-tools
      ++ cargoExtras;
  } // env);
}
