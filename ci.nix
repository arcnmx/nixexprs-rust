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
in {
  name = "nixexprs-rust";
  ci.gh-actions.enable = true;
  tasks = {
    releases.inputs = mapAttrs (_: rustPackages) channels.rust.releases;
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
      in ''
        nix-shell ${drv} --run "cargo --version"
      '';
      impure = true;
    };
  };
  channels.rust.path = src;
  jobs = listToAttrs (flip crossLists [ # build matrix
    [ # channels
      { nixpkgs = "unstable"; }
      { nixpkgs = "19.09"; name = "stable"; }
    ] [ # systems
      { system = "x86_64-linux"; }
      { system = "x86_64-darwin"; postfix = "-mac"; }
    ]
  ] ({ nixpkgs, name ? nixpkgs }: { system, postfix ? "" }: nameValuePair "${name}${postfix}" {
    inherit system;
    channels = { inherit nixpkgs; };
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

      # build and run a bare-metal arm example
      # try it out! `nix run ci.job.cross-arm.test.cortex-m`
      tasks.cortex-m.inputs = channels.rust.stable.buildRustPackage rec {
        pname = "cortex-m-quickstart";
        version = "2019-08-13";
        src = channels.cipkgs.fetchFromGitHub {
          owner = "rust-embedded";
          repo = pname;
          rev = "3ca2bb9a4666dabdd7ca73c6d26eb645cb018734";
          sha256 = "0rf220rsfx10zlczgkfdvhk1gqq2gwlgysn7chd9nrc0jcj5yc7n";
        };

        cargoPatches = [ ./ci/cortex-m-quickstart-lock.patch ];
        cargoSha256 = "1l1js8lx0sfhfvf2dm64jpv4vsh4bvsyyqmcniq7w9z8hi52aixr";

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
}
