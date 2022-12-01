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
    versionAtLeast channel.version "1.46"
  ) channels.rust.releases;
in {
  name = "nixexprs-rust";
  ci.gh-actions.enable = true;
  tasks = {
    releases.inputs = mapAttrs (_: rustPackages) releasesToTest;
    impure.inputs = mapAttrs (_: rustPackages) {
      inherit (channels.rust) stable beta;
    };
    nightly = {
      inputs = mapAttrs (_: rustPackages) {
        inherit (channels.rust) nightly;
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
      { nixpkgs = "22.11"; name = "stable"; }
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
      channels.nixpkgs.args = {
        localSystem = "x86_64-linux";
        crossSystem = systems.examples.arm-embedded // {
          platform.rust.target = "thumbv7m-none-eabi";
        };
        config.allowUnsupportedSystem = true;
      };
      nixpkgs = "unstable";

      tasks = mkForce {
        # build and run a bare-metal arm example
        # try it out! `nix run ci.job.cross-arm.test.cortex-m`
        cortex-m.inputs = channels.rust.stable.buildRustPackage rec {
          pname = "cortex-m-quickstart";
          version = "2019-08-13";
          src = channels.cipkgs.fetchFromGitHub {
            owner = "rust-embedded";
            repo = pname;
            rev = "3ca2bb9a4666dabdd7ca73c6d26eb645cb018734";
            sha256 = "0rf220rsfx10zlczgkfdvhk1gqq2gwlgysn7chd9nrc0jcj5yc7n";
          };

          cargoPatches = [ ./ci/cortex-m-quickstart-lock.patch ];
          cargoSha256 = "16gmfq6v7qqa2xzshjbgpffygvf7nd5qn31m0b696rnwfj4rxlag";

          buildType = "debug";
          postBuild = ''
            doCheck=true
          ''; # nixpkgs cross builds force doCheck=false :(

          nativeBuildInputs = [ channels.cipkgs.qemu ]; # this should be checkInputs but...
          checkPhase = ''
            sed -i -e 's/# runner = "qemu/runner = "qemu/' .cargo/config
            cargo run -v --example hello
          '';

          meta.platforms = platforms.all;
        };
      };
    };
  };
}
