{ self, lib, pkgs, ... }: {
  distChannel = pkgs.callPackage ({
    stdenv, fetchcargo, pkgs, buildPackages, targetPackages, buildRustCrate
    , sha256 ? null, channel ? null /* "stable" */, date ? null
  }@args: let
    manifestFile = self.manifestFile {
      inherit sha256;
      url = self.manifest_v2_url args;
    };
    isAvailable = tools: name: tools ? ${name} && tools.${name}.meta.broken or false != true;
    channelBuilder = { stdenv, pkgs, buildPackages, targetPackages, fetchcargo, buildRustCrate, rlib }: cself: {
      inherit manifestFile channel date;
      inherit (cself.rustc-unwrapped) version;
      manifest = rlib.manifestTargets (cself.manifestFile);

      context = {
        inherit stdenv pkgs buildPackages targetPackages rlib;
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
      hostTarget = rlib.rustTargetEnvironment { inherit stdenv; };
      buildTarget = rlib.rustTargetEnvironment { inherit (buildPackages) stdenv; };
      targetTarget = rlib.rustTargetEnvironment (
        { inherit (targetPackages) stdenv; }
        // lib.optionalAttrs (cself.targetRustLld) { linker = null; }
      );
      tools = cself.manifest.targetForPlatform stdenv.hostPlatform;
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
      rustc-unwrapped = cself.tools.rustc;
      cargo-unwrapped = cself.tools.cargo;
      rust-src = rlib.wrapRustSrc { inherit (cself.tools) rust-src; };
      rust-sysroot = rlib.rustSysroot {
        std = cself.sysroot-std;
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
        target = cself.targetTarget; # TODO: or hostTarget?
        inner = cself.tools.llvm-tools or cself.tools.llvm-tools-preview; # TODO: make sure renames work in manifestTargets instead!
      };
      bintools = rlib.wrapLlvmBintools {
        # for use with cargo-binutils
        inner = cself.llvm-tools;
      };
      cargo-binutils = pkgs.cargo-binutils.override { inherit (cself) bintools; };
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
      miri = rlib.wrapMiri.override { xargo = pkgs.xargo-unwrapped or pkgs.xargo; } {
        inherit (cself.tools) miri;
        inherit (cself) rust-src rustc cargo;
      };
      inherit (cself.tools) clippy rustfmt;
      rls-sysroot = rlib.wrapRlsSysroot {
        inherit (cself.tools) rust-src rust-analysis;
        inherit (cself) rust-sysroot;
      };
      rls = rlib.wrapRls {
        inherit (cself.tools) rls;
        inherit (cself) rls-sysroot rustc;
      };

      # build support
      mkShell = rlib.mkShell.override { inherit (cself) rustPlatform; };
      fetchcargo = fetchcargo.override {
        inherit (cself.buildTools) cargo;
      };
      buildRustCrate = buildRustCrate.override {
        # TODO: rlib.buildRustCrate!
        inherit (cself.buildTools) rustc;
      };
      rustPlatform = builtins.removeAttrs cself.buildChannel ["rustPlatform"] // rlib.makeRustPlatform.override {
        inherit stdenv;
        inherit (cself) fetchcargo;
      } {
        inherit (cself.buildChannel) cargo rustc rust-src;
      } // {
        inherit (cself) fetchcargo mkShell buildRustCrate;
        inherit (cself) buildChannel targetChannel;
        hostChannel = cself;
      };
      inherit (cself.rustPlatform) buildRustPackage rust rustcSrc;

      # buildPackages and targetPackages variants
      # TODO: UGH PROBLEM HERE IS IF YOU EXTEND CSELF, YOU DON'T ALSO GET TO EXTEND THESE FOR FREE!!!
      # So if you set some setting, it will only apply for the hostChannel which usually isn't even what you want :(
      # offer a (global? or at least nested that applies to current and all under) channel overlay?
      buildChannel = lib.makeExtensible (channelBuilder {
        inherit (buildPackages) stdenv pkgs buildPackages targetPackages fetchcargo buildRustCrate;
        rlib = rlib.buildLib;
      });
      targetChannel = lib.makeExtensible (channelBuilder {
        inherit (targetPackages) stdenv pkgs buildPackages targetPackages fetchcargo buildRustCrate;
        rlib = rlib.targetLib;
      });
    };
  in lib.makeExtensible (channelBuilder {
    inherit stdenv pkgs buildPackages targetPackages fetchcargo buildRustCrate;
    rlib = self;
  })) { };
}
