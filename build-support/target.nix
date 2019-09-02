{ pkgs, lib, self, ... }: let
  ccEnvVar = n: builtins.replaceStrings [ "-" ] [ "_" ] n;
  cargoEnvVar = n: ccEnvVar (lib.toUpper n);
in {
  rustTargetEnvironment = lib.makeOverridable ({
    pkgs ? null
  , stdenv ? pkgs.stdenv
  , triple ? self.rustTargetFor stdenv.hostPlatform
  , stdenvCc ? (if builtins.isString stdenv then pkgs.${stdenv} else stdenv).cc
  , ar ? "${stdenvCc.bintools.bintools}/bin/${stdenvCc.targetPrefix}ar"
  , cc ? "${stdenvCc}/bin/${stdenvCc.targetPrefix}cc"
  , cxx ? "${stdenvCc}/bin/${stdenvCc.targetPrefix}c++"
  , linker ?
    if linkerFlavor == "gcc" then "${stdenvCc}/bin/${stdenvCc.targetPrefix}cc"
    else if linkerFlavor == "ld" then "${stdenvCc}/bin/${stdenvCc.targetPrefix}ld"
    else throw "unknown linker for ${linkerFlavor}"
  , linkerFlavor ? # em gcc ld msvc ptx-linker wasm-ld ld64.lld ld.lld lld-link
    if stdenvCc.isGNU || stdenvCc.isClang then "gcc" else throw "unknown linker for ${stdenv.name}"
  , rustcFlags ?
    if triple == "i686-pc-windows-gnu" then [ "-C" "panic=abort" ] else [] # TODO: compile gcc without sjlj exceptions so this doesn't happen? or just compile libstd from source tbh, it shouldn't be that bad?
  }: {
    inherit triple stdenv ar cc cxx linker linkerFlavor rustcFlags;
  });

  targetForSystem = {
    armv5tel-linux = "arm-unknown-linux-gnueabi";
    mips64el-linux = "mips64el-unknown-linux-gnuabi64";
    i686-darwin = "i686-apple-darwin";
    x86_64-darwin = "x86_64-apple-darwin";
    i686-cygwin = "i686-pc-windows-gnu"; # or msvc?
    x86_64-cygwin = "x86_64-pc-windows-gnu"; # or msvc?
    x86_64-freebsd = "x86_64-unknown-freebsd";
  };

  targetForConfig = {
    i686-pc-mingw32 = "i686-pc-windows-gnu";
    x86_64-pc-mingw32 = "x86_64-pc-windows-gnu";
    i686-apple-ios = "i386-iphone-ios";
    armv6m-none-eabi = "thumbv6m-none-eabi";
    armv7m-none-eabi = "thumbv7m-none-eabi";
    armv7em-none-eabi = "thumbv7em-none-eabi";
    armv7em-none-eabihf = "thumbv7em-none-eabihf";
    armv7a-apple-ios = "armv7-apple-ios";
    wasm32-unknown-wasi = "wasm32-wasi";
    armv7a-unknown-linux-androideabi = "armv7-linux-androideabi";
    armv6l-unknown-linux-gnueabi = "arm-unknown-linux-gnueabi";
    armv6l-unknown-linux-gnueabihf = "arm-unknown-linux-gnueabihf";
    armv6l-unknown-linux-musleabi = "arm-unknown-linux-musleabi";
    armv6l-unknown-linux-musleabihf = "arm-unknown-linux-musleabihf";
  };

  rustTargetFor = platform:
    self.targetForConfig.${platform.config}
    or self.targetForSystem.${platform.system}
    or platform.config;
} // lib.mapAttrs (_: lib.flip pkgs.callPackage { }) {
  # for gcc/cc-rs, the build support crate
  rustCcEnv = { lib, stdenv }@cp: with lib; {
    stdenv ? cp.stdenv
  , target ? self.rustTargetEnvironment { inherit stdenv; }
  }: {
    ${mapNullable (_: "AR_${ccEnvVar target.triple}") target.ar} = target.ar;
    ${mapNullable (_: "CC_${ccEnvVar target.triple}") target.cc} = target.cc;
    ${mapNullable (_: "CXX_${ccEnvVar target.triple}") target.cxx} = target.cxx;
  };

  cargoEnv = { lib, stdenv }@cp: with lib; {
    default ? false
  , stdenv ? cp.stdenv
  , target ? self.rustTargetEnvironment { inherit stdenv; }
  }: let
    rustFlags = target.rustcFlags
      ++ optionals (target.linker != null) [ "-C" "linker-flavor=${target.linkerFlavor}" ];
  in {
    ${if rustFlags != [] then "CARGO_TARGET_${cargoEnvVar target.triple}_RUSTFLAGS" else null} = rustFlags;
    ${mapNullable (_: "CARGO_TARGET_${cargoEnvVar target.triple}_LINKER") target.linker} = target.linker;
    ${mapNullable (_: "CARGO_TARGET_${cargoEnvVar target.triple}_AR") target.ar} = target.ar;
    ${if default then "CARGO_BUILD_TARGET" else null} = target.triple; # TODO: this doesn't work well when mixed with cargo test/run/etc...
    #"CRATE_CC_NO_DEFAULTS_${cargoEnvVar target.triple}" = "1"; # stdenv can maybe manage this for us..?
    # TODO: LDFLAGS = "-fuse-ld=gold" and lld and things?
  };

  #setupEnvironmentHook = { lib, writeTextFile }: env: with lib; writeTextFile {
  #  name = "rust-env-hook.sh";
  #  destination = "/nix-support/setup-hook";
  #  text = concatStringsSep "\n" (mapAttrsToList (k: v: ''export ${k}="${toString v}"'') env);
  #  # TODO: targetOffset stuff?
  #};

  rustSysroot = { lndir, stdenvNoCC, windows ? null }: { std ? [] }: with stdenvNoCC.lib; lib.drvRec (drv: stdenvNoCC.mkDerivation {
    pname = "rust-sysroot";
    version = (builtins.head std).version;
    name = "rust-sysroot-${drv.version}";

    preferLocalBuild = true;
    nativeBuildInputs = [ lndir ];
    buildInputs = toList std;
    propagatedBuildInputs = optional (any (std: std.stdenv.hostPlatform.config == "i686-pc-mingw32") std) (windows.mingw_w64_pthreads.overrideAttrs (_: { dontDisableStatic = true; })); # TODO: https://github.com/rust-lang/rust/blob/4268e7ee22935f086b856ef0063a9e22b49aeddb/src/libunwind/build.rs#L35 insists on trying to link this statically...
    # TODO: also need to change gcc to build with --disable-sjlj-exceptions: https://github.com/NixOS/nixpkgs/blob/1ca86b405699183ff2b00be42281a81ea1744f41/pkgs/development/compilers/gcc/7/default.nix#L99

    std = lib.findInput drv.buildInputs std;

    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/nix-support
      for dir in $std; do
        lndir -silent $dir $out
      done
    '';

    #setupHook = builtins.toFile "rust-sysroot-setup-hook.sh" ''
    #  # TODO: figure out targetOffset?
    #  export RUSTC_SYSROOT=@out@
    #'';
  });

  wrapRustc = { stdenvNoCC, makeWrapper }: { rustc, sysroot ? null, ... }@args: lib.drvRec (drv: stdenvNoCC.mkDerivation ({
    pname = "rustc-wrapped";
    inherit (rustc) version;

    preferLocalBuild = true;
    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ rustc ];
    depsTargetTarget = [ sysroot ];

    rustc = lib.findInput drv.buildInputs rustc;
    rustcTarget = drv.rustc.rust.target.target;
    sysroot = lib.optional (sysroot != null) (lib.findInput drv.depsTargetTarget sysroot);

    unpackPhase = "true";
    installPhase = assert stdenvNoCC.hostPlatform.isLinux; ''
      if [[ -n $sysroot ]]; then
        extraRustcArgs=(
          --set-default RUSTC_SYSROOT $sysroot
        )
      fi
      extraRustcArgs+=(
        --run '[[ -z $RUSTC_SYSROOT ]] || extraFlagsArray+=(--sysroot $RUSTC_SYSROOT)'
        --run '[[ -z $RUSTC_TARGET ]] || extraFlagsArray+=(--target $RUSTC_TARGET)'
        --run '[[ -z $RUSTC_FLAGS ]] || extraFlagsArray+=($RUSTC_FLAGS)'
      )

      mkdir -p $out/bin
      makeWrapper $rustc/bin/rustc $out/bin/rustc --argv0 '$0' \
        "''${extraRustcArgs[@]}"

      makeWrapper $rustc/bin/rustdoc $out/bin/rustdoc --argv0 '$0' \
        --prefix PATH : $out \
        "''${extraRustcArgs[@]}"

      rustLld=$rustc/lib/rustlib/$rustcTarget/bin/rust-lld
      if [[ -e $rustLld ]]; then
        ln -s $rustLld $out/bin/rust-lld
      fi
    '';

    postFixup = ''
      # pass on propagated deps and setup hooks without affecting PATH
      mkdir -p $out/nix-support
      for f in $rustc/nix-support/*; do
        cat $f >> $out/nix-support/$(basename $f)
      done
    '';
  } // builtins.removeAttrs args [ "rustc" "sysroot" ]));

  wrapCargo = { stdenvNoCC, makeWrapper }: { rustc, cargo, cargoEnv ? { }, ... }@args: lib.drvRec (drv: stdenvNoCC.mkDerivation ({
    pname = "cargo-wrapped";
    inherit (cargo) version;

    preferLocalBuild = true;
    nativeBuildInputs = [ makeWrapper ];
    propagatedBuildInputs = [ rustc ];
    buildInputs = [ cargo ];

    rustc = lib.findInput drv.propagatedBuildInputs rustc;
    cargo = lib.findInput drv.buildInputs cargo;

    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      makeWrapper $cargo/bin/cargo $out/bin/cargo --argv0 '$0' \
        ${with lib; concatStringsSep " " (flatten (mapAttrsToList (k: v: [ "--set-default" k ''"${toString v}"'' ]) cargoEnv))} \
        --prefix PATH : $rustc/bin
        #--set-default RUSTC $rustc/bin/rustc
        #--set-default RUSTDOC $rustc/bin/rustdoc
    '';

    postFixup = ''
      # pass on propagated deps and setup hooks without affecting PATH
      mkdir -p $out/nix-support
      for f in $cargo/nix-support/*; do
        cat $f >> $out/nix-support/$(basename $f)
      done
    '';
  } // builtins.removeAttrs args [ "rustc" "cargo" "cargoEnv" ]));

  wrapTargetBin = { stdenvNoCC }: { target, inner }: lib.drvRec (drv: stdenvNoCC.mkDerivation {
    pname = "${inner.pname}-wrapped";
    inherit (inner) version;

    buildInputs = [ inner ];

    inner = lib.findInput drv.buildInputs inner;
    inherit (target) triple;

    buildCommand = ''
      mkdir -p $out/bin
      [[ ! -e $inner/bin ]] || ln -s $inner/bin/* $out/bin/
      [[ ! -e $inner/lib/rustlib/$triple/bin ]] || ln -s $inner/lib/rustlib/$triple/bin/* $out/bin/
    '';
  });

  wrapLlvmBintools = { stdenvNoCC }: { inner }: lib.drvRec (drv: stdenvNoCC.mkDerivation {
    pname = "${inner.pname}-wrapped";
    inherit (inner) version;

    buildInputs = [ inner ];

    inner = lib.findInput drv.buildInputs inner;

    buildCommand = ''
      mkdir -p $out/bin
      for binary in $inner/bin/llvm-*; do
        filename=$(basename $binary)
        [[ ! -L $binary ]] || binary=$(readlink -e $binary)
        ln -s $binary $out/bin/''${filename#llvm-}
      done
    '';
  });

  makeRustPlatform = { path, lib, makeRustPlatform, stdenv, cacert, git, fetchcargo }: { cargo, rustc, rust-src }: makeRustPlatform {
    inherit cargo rustc;
  } // {
    rustcSrc = rust-src;
    buildRustPackage = self.buildRustPackage.override {
      inherit path lib stdenv cacert git fetchcargo rustc cargo;
    };
  };
}
