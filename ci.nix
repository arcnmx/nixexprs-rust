{ config, pkgs, channels, lib, ... }: with lib; let
  stable = "23.11";
  src = channels.cipkgs.nix-gitignore.gitignoreSourcePure [ ''
    /ci.nix
    /ci/
    /.github
    /.git
  '' ./.gitignore ] ./.;
  rustPackages = channel: with channel.rustPlatform; {
    inherit rustc cargo
      llvm-tools rust-analyzer gdb lldb;
    miri = miri.overrideAttrs (old: {
      passthru = old.passthru or {} // {
        ci = old.passthru.ci or {} // {
          warn = true;
        };
      };
    });
  };
  releasesToTest = {
    # limit the releases tested due to disk space limitations when building/downloading
    inherit (channels.rust.releases) "1.74.1" "1.76.0";
    inherit (channels.rust) latest;
  };
  mkReleaseTask = channel: {
    inputs.release = rustPackages channel;
    cache.wrap = true;
  };
  defaultTasks = {
    impure = {
      inputs = mapAttrs (_: rustPackages) {
        inherit (channels.rust) stable beta;
      };
      cache.wrap = true;
    };
    nightly = {
      inputs = mapAttrs (_: rustPackages) {
        inherit (channels.rust) nightly unstable;
      };
      warn = true;
      cache.wrap = true;
    };
    shell.inputs.stable = pkgs.ci.command {
      name = "shell";
      command = let
        shell = channels.rust.stable.mkShell {};
        drv = builtins.unsafeDiscardStringContext shell.drvPath;
        importFile = pkgs.writeText "shell.nix" ''
          import ${drv}
        '';
      in ''
        nix-shell ${importFile} --run "cargo --version"
      '';
      impure = true;
    };
  };
in {
  name = "nixexprs-rust";
  ci = {
    version = "v0.7";
    gh-actions.enable = true;
  };
  channels.rust.path = src;
  cache.cachix.ci = {
    enable = true;
    signingKey = "";
  };
  nix.config = {
    # trying to prevent downloads stalling...
    max-jobs = 2;
  };
  jobs = let
    mkRustVersion = version:
      if version == channels.rust.latest.version then "stable"
      else versions.majorMinor version;
    mkName = { nixpkgs, system, release, ... }:
      "rust"
      + optionalString (release != null) " ${mkRustVersion release.version}"
      + " (nixpkgs-" + (if nixpkgs == stable then "stable" else nixpkgs)
      + optionalString (hasSuffix "-darwin" system) "-macos"
      + ")";
    mkAttrName = { nixpkgs, system, release }: replaceStrings [ "." ] [ "_" ] (
      "nixpkgs-${nixpkgs}"
      + optionalString (release != null) "-rust-${mkRustVersion release.version}"
      + "-${system}"
    );
    mkJob = { nixpkgs, system, release }@args: nameValuePair (mkAttrName args) {
      inherit system;
      ci.gh-actions.name = mkName args;
      channels = { inherit nixpkgs; };
      tasks = if release == null then defaultTasks else {
        release = mkReleaseTask release;
      };
      warn = hasSuffix "-darwin" system;
    };
    matrix = lib.cartesianProduct or cartesianProductOfSets {
      nixpkgs = [ "unstable" stable ];
      system = [ "x86_64-linux" "aarch64-darwin" ];
      release = attrValues releasesToTest ++ [ null ];
    } ++ singleton {
      system = "x86_64-darwin";
      nixpkgs = stable;
      release = null;
    };
  in listToAttrs (map mkJob matrix) // {
    cross-arm = { channels, pkgs, ... }: {
      system = "x86_64-linux";
      channels.nixpkgs.version = stable;
      channels.nixpkgs.args = {
        localSystem = "x86_64-linux";
        crossSystem = systems.examples.arm-embedded // {
          rustc.config = "thumbv7m-none-eabi";
        };
        config = {
          allowUnsupportedSystem = true;
          checkMetaRecursively = false;
        };
      };

      tasks = {
        # build and run a bare-metal arm example
        # try it out! `nix run ci.job.cross-arm.test.cortex-m`
        cortex-m = {
          inputs = channels.rust.stable.callPackage ./ci/cortex-m-quickstart/derivation.nix { };
          cache.inputs = with channels.rust.stable.buildChannel; [
            rustc cargo
          ];
        };
      };
    };
  };
}
