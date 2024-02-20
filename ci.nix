{ config, pkgs, channels, lib, ... }: with lib; let
  src = channels.cipkgs.nix-gitignore.gitignoreSourcePure [ ''
    /ci.nix
    /ci/
    /.github
    /.git
  '' ./.gitignore ] ./.;
  rustPackages = channel: with channel.rustPlatform; {
    inherit rustc cargo
      llvm-tools rls rust-analyzer gdb lldb;
    miri = miri.overrideAttrs (old: {
      passthru = old.passthru or {} // {
        ci = old.passthru.ci or {} // {
          warn = true;
        };
      };
    });
  };
  releasesToTest = filterAttrs (_: channel:
    # limit the releases tested due to disk space limitations when building/downloading
    versionAtLeast channel.version "1.74"
  ) channels.rust.releases;
in {
  name = "nixexprs-rust";
  ci = {
    version = "v0.7";
    gh-actions.enable = true;
  };
  tasks = {
    releases.inputs = mapAttrs (_: rustPackages) releasesToTest;
    impure.inputs = mapAttrs (_: rustPackages) {
      inherit (channels.rust) stable beta;
    };
    nightly = {
      inputs = mapAttrs (_: rustPackages) {
        inherit (channels.rust) nightly unstable;
      };
      warn = true;
      cache.enable = false;
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
  channels.rust.path = src;
  jobs = listToAttrs (flip crossLists [ # build matrix
    [ # channels
      { nixpkgs = "unstable"; }
      { nixpkgs = "23.11"; name = "stable"; }
    ] [ # systems
      { system = "x86_64-linux"; }
      { system = "x86_64-darwin"; postfix = "-mac"; }
    ]
  ] ({ nixpkgs, name ? nixpkgs }: { system, postfix ? "" }: nameValuePair "${name}${postfix}" {
    inherit system;
    channels = { inherit nixpkgs; };
    warn = system == "x86_64-darwin";
  })) // {
    cross-arm = { channels, pkgs, ... }: {
      system = "x86_64-linux";
      channels.nixpkgs.version = "22.11";
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

      tasks = mkForce {
        # build and run a bare-metal arm example
        # try it out! `nix run ci.job.cross-arm.test.cortex-m`
        cortex-m.inputs = channels.rust.stable.callPackage ./ci/cortex-m-quickstart/derivation.nix { };
      };
    };
  };
}
