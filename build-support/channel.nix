{ self, buildSelf, lib, pkgs, ... }: {
  distChannel = pkgs.callPackage ({
    stdenv, fetchcargo, buildPackages, targetPackages, buildRustCrate
    , sha256 ? null, channel ? null /* "stable" */, date ? null
  }@args: lib.makeExtensible (cself: {
    manifest = with lib;
      self.manifestTargets (self.manifestFile {
        inherit sha256;
        url = self.manifest_v2_url args;
      });
    targetRustLld = false; # TODO: figure out which platforms rust currently uses rust-lld by default? Also this should just be part of the target spec or something, it needs to apply to host/build as well!
    hostTarget = self.rustTargetEnvironment { inherit stdenv; };
    buildTarget = self.rustTargetEnvironment { inherit (buildPackages) stdenv; };
    targetTarget = self.rustTargetEnvironment (
      { inherit (targetPackages) stdenv; }
      // lib.optionalAttrs (cself.targetRustLld) { linker = null; }
    );
    hostTools = cself.manifest.host;
    buildTools = cself.manifest.build;
    targetTools = cself.manifest.target;
    sysroot-std = [ cself.hostTools.rust-std cself.buildTools.rust-std cself.targetTools.rust-std ];
    rustc-unwrapped = cself.hostTools.rustc;
    cargo-unwrapped = cself.hostTools.cargo;
    rust-src = cself.hostTools.rust-src;
    rust-sysroot = self.rustSysroot {
      std = lib.unique cself.sysroot-std;
    };
    llvm-tools = self.wrapTargetBin {
      target = cself.hostTarget;
      inner = cself.hostTools.llvm-tools or cself.hostTools.llvm-tools-preview;
    };
    bintools = self.wrapLlvmBintools {
      # for use with cargo-binutils
      inner = cself.llvm-tools;
    };
    rust-cc =
      self.rustCcEnv { target = cself.buildTarget; }
      // self.rustCcEnv { target = cself.hostTarget; }
      // self.rustCcEnv { target = cself.targetTarget; };
    cargo-cc =
      self.cargoEnv { target = cself.buildTarget; }
      // self.cargoEnv { target = cself.hostTarget; }
      // self.cargoEnv { target = cself.targetTarget; default = true; };
    rustc = self.wrapRustc {
      rustc = cself.rustc-unwrapped;
      sysroot = cself.rust-sysroot;
    };
    cargo = self.wrapCargo {
      cargo = cself.cargo-unwrapped;
      cargoEnv = cself.cargo-cc // cself.rust-cc;
      inherit (cself) rustc;
    };
    fetchcargo = fetchcargo.override {
      inherit (cself) cargo;
    };
    buildRustCrate = buildRustCrate.override {
      # TODO: self.buildRustCrate!
      inherit (cself) rustc;
    };
    rustPlatform = cself;
  } // self.makeRustPlatform.override { inherit stdenv; inherit (cself) fetchcargo; } {
    inherit (cself) cargo rustc rust-src;
  })) { };
}
