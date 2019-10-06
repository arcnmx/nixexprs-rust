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
        inherit (channels.rust) stable beta;
      };
      warn = true;
      cache.enable = false;
    };
    shell = {
      inputs = {
        stable = pkgs.ci.command {
          name = "shell";
          command = ''
            nix-shell ${builtins.unsafeDiscardStringContext (channels.rust.stable.mkShell {}).drvPath} --run "cargo --version"
          '';
          impure = true;
        };
      };
    };
  };
  channels.rust.path = src;
  jobs = {
    unstable = {
      system = "x86_64-linux";
      channels.nixpkgs = "unstable";
    };
    unstable-mac = {
      system = "x86_64-darwin";
      channels.nixpkgs = "unstable";
    };
    beta = {
      system = "x86_64-linux";
      channels.nixpkgs = "19.09";
    };
    beta-mac = {
      system = "x86_64-darwin";
      channels.nixpkgs = "19.09";
    };
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
        cargoSha256 = "150glikhl5g8cwyq10piaa9r7yly6g57086qjdgv16r52wybvvqz";

        buildType = "debug";
        postBuild = ''
          doCheck=true # nixpkgs cross builds force doCheck=false :(
        '';

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
