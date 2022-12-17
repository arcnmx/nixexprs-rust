{ self, lib, pkgs, ... }: {
  distChannel = pkgs.callPackage ({
    stdenv, hostPlatform ? stdenv.hostPlatform, targetPlatform ? stdenv.targetPlatform, pkgs, buildPackages, targetPackages, buildRustCrate
  , sha256 ? null, rustToolchain ? null, channel ? null /* "stable"? */, date ? null, staging ? false, manifestPath ? null
  , rustcDev ? false # include "rustc-dev" component in sysroot
  , channelOverlays ? []
  }@args: let
    broken = name: pkgs.runCommand name {
      version = "0";
      meta.broken = true;
    } "echo tool ${name} missing from ${hostPlatform.config} >&2";
    isAvailable = tools: name: tools ? ${name} && tools.${name}.meta.broken or false != true;
    makeExtensibleChannel = overlays: builder: builtins.foldl' (c: o: c.extend o) (lib.makeExtensible builder) overlays;
    channelBuilder = { stdenv, hostPlatform, targetPlatform, pkgs, buildPackages, targetPackages, buildRustCrate, rlib }: cself: {
      manifestArgs = lib.optionalAttrs (rustToolchain != null) (rlib.parseRustToolchain rustToolchain) // {
        distRoot = rlib.distRoot;
      } // lib.retainAttrs args [ "date" "channel" "staging" ];
      manifestUrl = rlib.manifest_v2_url cself.manifestArgs;
      manifestPath = rlib.manifestPath {
        inherit channel sha256;
        path = args.manifestPath or null;
        url = cself.manifestUrl;
      };
      inherit channel date;
      inherit (cself.rustc-unwrapped) version;
      manifest = rlib.manifestTargets (cself.manifestPath);

      context = {
        inherit stdenv hostPlatform targetPlatform pkgs buildPackages targetPackages rlib;
      };

      # Rough layout here:
      # 1. pkgs.rustChannel.stable (or any other distChannel):
      #    1. Derivations are all for the host (same way pkgs.gcc is host gcc, not build gcc)
      #    2. Functions are all for generating target derivations (same way pkgs.stdenv, all builders, etc work)
      # 2. buildChannel is the buildPackages equivalent, where buildChannel.rustc is usually what you want in a builder.
      # 3. targetChannel is the targetPackages equivalent, and rarely what you want unless you're traversing back from a buildChannel or something.
      # 4. rustPlatform serves the same purpose as pkgs.rustPlatform, but contains an interesting mix:
      #    1. Functions are all for generating target derivations like normal (compatible with pkgs.rustPlatform.buildRustPackage)
      #    2. Derivations are all from buildChannel! So rustPlatform.rustc is the native builder variant.
      #    3. hostChannel also exists as a way to find your way back

      # target configuration
      # TODO: use https://github.com/rust-lang/rustup-components-history/blob/master/README.md#the-web-part to decide what nightly to download if certain features are required?
      targetRustLld = false; # TODO: figure out which platforms rust currently uses rust-lld by default? Also this should just be part of the target spec or something, it needs to apply to host/build as well!
      # TODO: offer some way to use lld as the linker without having stdenv link the entire world with it?
      hostTarget = rlib.rustTargetEnvironment { inherit stdenv hostPlatform; };
      buildTarget = rlib.rustTargetEnvironment { inherit (buildPackages) stdenv hostPlatform; };
      targetTarget = rlib.rustTargetEnvironment (
        { inherit (targetPackages) stdenv hostPlatform; }
        // lib.optionalAttrs (cself.targetRustLld) { linker = null; }
      );
      available = cself.manifest.targets ? ${cself.hostTarget.triple};
      toolsAvailable = cself.available && isAvailable cself.tools "rustc";
      tools = cself.manifest.targetForPlatform cself.hostTarget.triple;
      hostTools = cself.tools; # alias necessary?
      buildTools = cself.buildChannel.tools;
      targetTools = cself.targetChannel.tools;
      rust-cc =
        rlib.rustCcEnv { target = cself.buildTarget; }
        // rlib.rustCcEnv { target = cself.hostTarget; }
        // rlib.rustCcEnv { target = cself.targetTarget; };
      cargo-cc =
        rlib.cargoEnv { target = cself.buildTarget; }
        // rlib.cargoEnv { target = cself.hostTarget; }
        // rlib.cargoEnv { target = cself.targetTarget; default = true; };

      # rust
      sysroot-std = lib.unique [ cself.hostTools.rust-std cself.buildTools.rust-std cself.targetTools.rust-std ];
      sysroot-dev = let
        tools = [ cself.hostTools.rustc-dev or null cself.buildTools.rustc-dev cself.targetTools.rustc-dev or null ];
      in lib.optionals rustcDev (
        lib.unique (lib.filter (t: t != null && t.meta.broken or false != true) tools)
      );
      rustc-unwrapped = cself.tools.rustc or (broken "rustc");
      cargo-unwrapped = cself.tools.cargo or (broken "cargo");
      rust-src = rlib.wrapRustSrc { inherit (cself.tools) rust-src; };
      rust-sysroot = rlib.rustSysroot {
        std = cself.sysroot-std;
        dev = cself.sysroot-dev;
      };
      rustc = rlib.wrapRustc {
        rustc = cself.rustc-unwrapped;
        sysroot = cself.rust-sysroot;
      };
      cargo = rlib.wrapCargo {
        cargo = cself.cargo-unwrapped;
        cargoEnv = cself.cargo-cc // cself.rust-cc;
        inherit (cself) rustc;
      };

      # bundled tools and customized overrides
      llvm-tools = rlib.wrapTargetBin {
        target = cself.hostTarget;
        inner = cself.tools.llvm-tools or cself.tools.llvm-tools-preview; # TODO: make sure renames work in manifestTargets instead!
      };
      bintools = rlib.wrapLlvmBintools {
        # for use with cargo-binutils
        inner = cself.llvm-tools;
      };
      cargo-binutils = rlib.wrapCargoBinutils {
        inner = pkgs.cargo-binutils or pkgs.cargo-binutils-unwrapped or null;
        inherit (cself) bintools;
      };
      xargo = pkgs.xargo.override {
        inherit (cself) rustc cargo;
        rustcSrc = cself.rust-src;
      };
      gdb-unwrapped = pkgs.gdb;
      gdb = rlib.wrapGdb.override { gdb = cself.gdb-unwrapped; } {
        inherit (cself) rustc-unwrapped;
      };
      lldb-unwrapped = if isAvailable cself.tools "lldb-preview" then cself.tools.lldb-preview else pkgs.lldb;
      lldb = rlib.wrapGdb.override { gdb = cself.lldb-unwrapped; } {
        inherit (cself) rustc-unwrapped;
      };
      miri-unwrapped = cself.tools.miri or cself.tools.miri-preview or (broken "miri");
      miri = rlib.wrapMiri.override { xargo = pkgs.xargo-unwrapped or pkgs.xargo or null; } {
        miri = cself.miri-unwrapped;
        inherit (cself) rust-src rustc cargo;
      };
      rustfmt = cself.tools.rustfmt or (if isAvailable cself.tools "rustfmt-preview" then cself.tools.rustfmt-preview else pkgs.rustfmt);
      clippy = cself.tools.clippy or (if isAvailable cself.tools "clippy-preview" then cself.tools.clippy-preview else pkgs.clippy);
      rls-sysroot = rlib.wrapRlsSysroot {
        inherit (cself.tools) rust-src rust-analysis;
        inherit (cself) rust-sysroot;
      };
      rls-unwrapped = cself.tools.rls or (broken "rls");
      rls = rlib.wrapRls {
        rls = cself.rls-unwrapped;
        inherit (cself) rls-sysroot rustc;
      };
      rust-analyzer-unwrapped = cself.tools.rust-analyzer or pkgs.rust-analyzer-unwrapped;
      rust-analyzer = rlib.wrapRustAnalyzer {
        inherit (cself) rust-src rust-analyzer-unwrapped;
      };

      rust-analyzer-upstream = rlib.wrapRustAnalyzer {
        inherit (cself) rust-src;
        inherit (pkgs) rust-analyzer-unwrapped;
      };

      # build support
      mkShell = rlib.mkShell.override { inherit (cself) rustPlatform; };
      buildRustCrate = buildRustCrate.override {
        inherit (cself.buildTools) rustc;
      };
      rustPlatform = builtins.removeAttrs cself.buildChannel ["rustPlatform"] // rlib.makeRustPlatform.override {
        inherit stdenv;
      } {
        inherit (cself) rust;
        inherit (cself.buildChannel) cargo rustc rust-src;
      } // {
        inherit (cself) context mkShell buildRustCrate;
        inherit (cself) buildChannel targetChannel;
        hostChannel = cself;
      };
      rust = rlib.makeRust.override {
        inherit (cself.context.pkgs) newScope;
      } {
        packages = rec {
          prebuilt = {
            inherit (cself) rustPlatform rustc cargo clippy rustfmt;
          };
          ${channel} = prebuilt;
        };
        buildRust = cself.buildChannel.rust;
      } // cself.rustPlatform.rust;
      inherit (cself.rustPlatform) buildRustPackage rustcSrc;

      callPackage = pkgs.newScope {
        rustChannel = cself;
        inherit (cself)
          rust rustPlatform buildRustPackage buildRustCrate
          cargo rustc
        ;
      };

      # buildPackages and targetPackages variants
      buildChannel = makeExtensibleChannel channelOverlays (channelBuilder {
        inherit (buildPackages) stdenv hostPlatform targetPlatform pkgs buildPackages targetPackages buildRustCrate;
        rlib = rlib.buildLib;
      });
      targetChannel = makeExtensibleChannel channelOverlays (channelBuilder {
        inherit (targetPackages) stdenv hostPlatform targetPlatform pkgs buildPackages targetPackages buildRustCrate;
        rlib = rlib.targetLib;
      });
    };
  in makeExtensibleChannel channelOverlays (channelBuilder {
    inherit stdenv hostPlatform targetPlatform pkgs buildPackages targetPackages buildRustCrate;
    rlib = self;
  })) { };
}
