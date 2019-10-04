{ pkgs, lib, self, ... }: lib.mapAttrs (_: lib.flip pkgs.callPackage { }) {
  mkShell = { lib, buildPackages, mkShell, rustPlatform }: lib.makeOverridable ({
    allowBroken ? false # continue even if extra commands are missing or broken
  , rustfmtDist ? false # use rustfmt from the binary channel rather than from nixpkgs
  , cargoCommands ? [] # e.g. [ "bloat" "binutils" "fmt" "clippy" etc ]
  , rustTools ? [] # [ "llvm-tools" "rust-analyzer" "rls" "xargo" "gdb" "lldb" etc ]
  # TODO: enableRustLld? better to put that in the channel config though...
  , ...}@args: with lib; let
    name = "rust-shell";

    env = removeAttrs args [
      "rustfmtDist"
      "cargoCommands" "rustTools"
      "nativeBuildInputs"
    ];
    hasPackage = pkgs: attr: pkgs ? ${attr} &&
      pkgs.${attr}.meta.broken or false == false &&
      pkgs.${attr}.meta.available or true == true;
    tryPackage = pkgs: attr: if allowBroken && !hasPackage pkgs attr
      then builtins.trace "WARN: rustPlatform.mkShell omitting broken package ${attr}" null
      else pkgs.${attr};
    mapCargo = c: {
      "fmt" = if rustfmtDist && hasPackage rustPlatform "rustfmt" then
        tryPackage rustPlatform "rustfmt"
        else tryPackage buildPackages "rustfmt";
      "binutils" = tryPackage rustPlatform "cargo-binutils";
      "miri" = tryPackage rustPlatform "miri";
      "clippy" = tryPackage rustPlatform "clippy";
    }.${c} or (tryPackage buildPackages "cargo-${c}");
    mapTool = c: {
      #"rust-analyzer" = tryPackage buildPackages "rust-analyzer";
    }.${c} or (tryPackage rustPlatform c);
  in mkShell ({
    nativeBuildInputs = args.nativeBuildInputs or []
      ++ [ rustPlatform.rustc rustPlatform.cargo ]
      ++ map mapTool rustTools
      ++ map mapCargo cargoCommands;
  } // env));
}
