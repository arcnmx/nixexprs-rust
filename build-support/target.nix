{ pkgs, lib, self, ... }: let
  ccEnvVar = n: builtins.replaceStrings [ "-" ] [ "_" ] n;
  cargoEnvVar = n: ccEnvVar (lib.toUpper n);
  rust'lib = pkgs.rust.lib;
  makeWrapperEnv = env: with lib; concatStringsSep " " (flatten (
    mapAttrsToList (k: v: [ "--set-default" k ''"${toString v}"'' ]) env
  ));
in {
  rustTargetEnvironment = lib.makeOverridable ({
    pkgs ? null
  , stdenv ? pkgs.stdenv
  , hostPlatform ? pkgs.hostPlatform or stdenv.hostPlatform
  , triple ? self.rustTargetFor hostPlatform
  , stdenvCc ? stdenv.cc
  , ar ? "${stdenvCc.bintools.bintools}/bin/${stdenvCc.targetPrefix}ar"
  , cc ? "${stdenvCc}/bin/${stdenvCc.targetPrefix}${if stdenvCc.isClang or false then "clang" else "cc"}"
  , cxx ? "${stdenvCc}/bin/${stdenvCc.targetPrefix}${if stdenvCc.isClang or false then "clang++" else "c++"}"
  , linker ?
    if linkerFlavor == "gcc" then "${stdenvCc}/bin/${stdenvCc.targetPrefix}cc"
    else if linkerFlavor == "ld" then "${stdenvCc}/bin/${stdenvCc.targetPrefix}ld"
    else throw "unknown linker for ${linkerFlavor}"
  , linkerFlavor ? # em gcc ld msvc ptx-linker wasm-ld ld64.lld ld.lld lld-link
    if stdenvCc.isGNU || stdenvCc.isClang then "gcc" else throw "unknown linker for ${stdenv.name}"
  , rustcFlags ?
    if triple == "i686-pc-windows-gnu" then [ "-C" "panic=abort" ] else [] # TODO: compile gcc without sjlj exceptions so this doesn't happen? or just compile libstd from source tbh, it shouldn't be that bad?
  }: {
    inherit triple stdenv hostPlatform ar cc cxx linker linkerFlavor rustcFlags;
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
    i686-w64-mingw32 = "i686-pc-windows-gnu";
    x86_64-w64-mingw32 = "x86_64-pc-windows-gnu";
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
    armv7l-unknown-linux-gnueabihf = "armv7-unknown-linux-gnueabihf";
    riscv64-unknown-linux-gnu = "riscv64gc-unknown-linux-gnu";
  };

  rustTargetFor = platform:
    platform.rustc.config
    or platform.platform.rust.target
    or self.targetForConfig.${platform.config}
    or self.targetForSystem.${platform.system}
    or (rust'lib.toRustTarget platform);
} // lib.mapAttrs (_: lib.flip pkgs.callPackage { }) {
  # for gcc/cc-rs, the build support crate
  rustCcEnv = { lib, stdenv, hostPlatform ? stdenv.hostPlatform }@cp: with lib; {
    stdenv ? cp.stdenv
  , hostPlatform ? cp.hostPlatform
  , target ? self.rustTargetEnvironment { inherit stdenv hostPlatform; }
  }: {
    ${mapNullable (_: "AR_${ccEnvVar target.triple}") target.ar} = target.ar;
    ${mapNullable (_: "CC_${ccEnvVar target.triple}") target.cc} = target.cc;
    ${mapNullable (_: "CXX_${ccEnvVar target.triple}") target.cxx} = target.cxx;
  };

  cargoEnv = { lib, stdenv, hostPlatform ? stdenv.hostPlatform }@cp: with lib; {
    default ? false
  , stdenv ? cp.stdenv
  , hostPlatform ? cp.hostPlatform
  , target ? self.rustTargetEnvironment { inherit stdenv hostPlatform; }
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

  rustSysroot = { lib, lndir, stdenvNoCC, windows ? null }: { std ? [], dev ? [] }: with lib; stdenvNoCC.mkDerivation {
    pname = "rust-sysroot";
    version = (builtins.head std).version;

    preferLocalBuild = true;
    nativeBuildInputs = [ lndir ];
    buildInputs = toList std ++ toList dev;
    propagatedBuildInputs = optional (any (std: std.stdenv.hostPlatform.config == "i686-pc-mingw32") std) (windows.mingw_w64_pthreads.overrideAttrs (_: { dontDisableStatic = true; })); # TODO: https://github.com/rust-lang/rust/blob/4268e7ee22935f086b856ef0063a9e22b49aeddb/src/libunwind/build.rs#L35 insists on trying to link this statically...
    # TODO: also need to change gcc to build with --disable-sjlj-exceptions: https://github.com/NixOS/nixpkgs/blob/1ca86b405699183ff2b00be42281a81ea1744f41/pkgs/development/compilers/gcc/7/default.nix#L99

    std = lib.buildInput std;
    rustcDev = lib.buildInput dev;

    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/nix-support
      for dir in $std $rustcDev; do
        lndir -silent $dir $out
      done
    '';

    #setupHook = builtins.toFile "rust-sysroot-setup-hook.sh" ''
    #  # TODO: figure out targetOffset?
    #  export RUSTC_SYSROOT=@out@
    #'';
  };

  wrapRustc = { stdenvNoCC, makeWrapper }: { rustc, sysroot ? null, ... }@args: stdenvNoCC.mkDerivation ({
    pname = "rustc-wrapped";
    inherit (rustc) version;
    meta = rustc.meta // {
      meta.mainProgram = "rustc";
    };

    preferLocalBuild = true;
    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ rustc ];
    depsTargetTarget = [ sysroot ];

    rustc = lib.buildInput rustc;
    rustcTarget = rustc.rust.target.target;
    sysroot = lib.optional (sysroot != null) (lib.inputOffset "targetTarget" sysroot);

    unpackPhase = "true";
    installPhase = ''
      if [[ -n $sysroot ]]; then
        extraRustcArgs=(
          --set-default RUSTC_SYSROOT $sysroot
        )
      fi
      extraRustcArgs+=(
        --run '[[ -z $RUSTC_SYSROOT || $* = *--sysroot* ]] || set -- --sysroot "$RUSTC_SYSROOT" "$@"'
        --run '[[ -z $RUSTC_TARGET || $* = *--target* ]] || set -- --target "$RUSTC_TARGET" "$@"'
        --run '[[ -z $RUSTC_FLAGS ]] || set -- $RUSTC_FLAGS "$@"'
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
  } // builtins.removeAttrs args [ "rustc" "sysroot" ]);

  wrapCargo = { stdenvNoCC, makeWrapper }: { rustc, cargo, cargoEnv ? { }, ... }@args: stdenvNoCC.mkDerivation ({
    pname = "cargo-wrapped";
    inherit (cargo) version;
    meta = cargo.meta // {
      meta.mainProgram = "cargo";
    };

    preferLocalBuild = true;
    nativeBuildInputs = [ makeWrapper ];
    propagatedBuildInputs = [ rustc ];
    buildInputs = [ cargo ];

    rustc = lib.buildInput rustc;
    cargo = lib.buildInput cargo;

    unpackPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      makeWrapper $cargo/bin/cargo $out/bin/cargo --argv0 '$0' \
        ${makeWrapperEnv cargoEnv} \
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
  } // builtins.removeAttrs args [ "rustc" "cargo" "cargoEnv" ]);

  # NOTE: supports lldb too despite the name. to use with gdbgui, just use this as its gdb binary
  wrapGdb = { stdenvNoCC, makeWrapper, gdb }: { rustc-unwrapped }: stdenvNoCC.mkDerivation {
    pname = "${gdb.pname or (builtins.parseDrvName gdb.name).name}-rust";
    version = gdb.version or (builtins.parseDrvName gdb.name).version;
    inherit (gdb) meta;

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ gdb rustc-unwrapped ];
    gdb = lib.buildInput gdb;
    rustc = lib.buildInput rustc-unwrapped;

    buildCommand = ''
      mkdir -p $out/rustlib/etc/
      cp $rustc/lib/rustlib/etc/*.py $out/rustlib/etc/
      rustcGdb=$out/rustlib/etc

      mkdir -p $out/bin
      for g in $gdb/bin/*gdb; do
        makeWrapper $g $out/bin/$(basename $g) \
          --prefix PYTHONPATH : $rustcGdb \
          --run "set -- --directory=$rustcGdb -iex 'add-auto-load-safe-path $rustcGdb' \"\$@\""
      done

      for g in $gdb/bin/*lldb; do
        makeWrapper $g $out/bin/$(basename $g) \
          --run "set -- --one-line-before-file 'command script import $rustcGdb/lldb_rust_formatters.py' \"\$@\"" \
          --run "set -- --one-line-before-file 'type summary add --no-value --python-function lldb_rust_formatters.print_val -x \".*\" --category Rust' \"\$@\"" \
          --run "set -- --one-line-before-file 'type category enable Rust' \"\$@\""
      done
    '';
  };

  wrapTargetBin = { stdenvNoCC }: { target, inner }: stdenvNoCC.mkDerivation {
    pname = "${inner.pname}-wrapped";
    inherit (inner) version;
    meta = inner.meta // {
      mainProgram = inner.meta.mainProgram or inner.pname;
    };

    buildInputs = [ inner ];

    inner = lib.buildInput inner;
    inherit (target) triple;

    buildCommand = ''
      mkdir -p $out/bin
      [[ ! -e $inner/bin ]] || ln -s $inner/bin/* $out/bin/
      [[ ! -e $inner/lib/rustlib/$triple/bin ]] || ln -s $inner/lib/rustlib/$triple/bin/* $out/bin/
    '';
  };

  wrapRustSrc = { stdenvNoCC }: { rust-src }: lib.drvRec (drv: stdenvNoCC.mkDerivation {
    pname = "${rust-src.pname}-wrapped";
    inherit (rust-src) version;

    buildInputs = [ rust-src ];

    rustcSrc = lib.buildInput rust-src;

    buildCommand = ''
      install -d $out
      if [[ -d $rustcSrc/lib/rustlib/src/rust/src ]]; then
        ln -s $rustcSrc/lib/rustlib/src/rust/src/* $out/
      fi
      if [[ -d $rustcSrc/lib/rustlib/src/rust/library ]]; then
        ln -s $rustcSrc/lib/rustlib/src/rust/library/* $out/
      fi
    '';

    passthru.shellHook = ''
      export RUST_SRC_PATH=${drv}
      export XARGO_RUST_SRC=${drv}
    '';
  });

  wrapRustAnalyzer = { stdenvNoCC, makeWrapper }: { rust-src, rust-analyzer-unwrapped, cargoEnv ? { } }: stdenvNoCC.mkDerivation {
    pname = "rust-analyzer-wrapped";
    version = rust-analyzer-unwrapped.version or "unknown";

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ rust-src rust-analyzer-unwrapped ];

    rustcSrc = lib.buildInput rust-src;
    rustAnalyzer = lib.buildInput rust-analyzer-unwrapped;

    buildCommand = ''
      mkdir -p $out/bin
      makeWrapper $rustAnalyzer/bin/rust-analyzer $out/bin/rust-analyzer \
        ${makeWrapperEnv cargoEnv} \
        --set-default RUST_SRC_PATH "$rustcSrc"
    '';

    meta = rust-analyzer-unwrapped.meta or {} // {
      mainProgram = "rust-analyzer";
      broken = rust-analyzer-unwrapped == null || rust-analyzer-unwrapped.meta.broken or false;
    };
  };

  wrapRlsSysroot = { stdenvNoCC }: { rust-sysroot, rust-src, rust-analysis }: stdenvNoCC.mkDerivation {
    pname = "rls-sysroot";
    inherit (rust-src) version meta;

    buildInputs = [ rust-sysroot rust-src rust-analysis ];

    rustcSrc = lib.buildInput rust-src;
    rustSysroot = lib.buildInput rust-sysroot;
    rustAnalysis = lib.buildInput rust-analysis;

    buildCommand = ''
      mkdir -p $out/lib/rustlib/
      ln -s $rustcSrc/lib/rustlib/src $out/lib/rustlib/
      cp --no-preserve=mode -sRLt $out/ $rustSysroot/lib $rustAnalysis/lib
    '';
  };

  wrapRls = { stdenvNoCC, makeWrapper }: { rls, rls-sysroot, rustc }: stdenvNoCC.mkDerivation {
    pname = "rls-wrapped";
    version = if rls.version or null != null then rls.version else "unknown";

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ rls rls-sysroot rustc ];

    rls = lib.buildInput rls;
    rlsSysroot = lib.buildInput rls-sysroot;
    rustc = lib.buildInput rustc;

    buildCommand = ''
      mkdir -p $out/bin
      makeWrapper $rls/bin/rls $out/bin/rls \
        --set-default RUSTC "$rustc/bin/rustc" \
        --set-default SYSROOT "$rlsSysroot"
    '';
  };

  wrapLlvmBintools = { stdenvNoCC }: { inner }: stdenvNoCC.mkDerivation {
    pname = "${inner.pname}-wrapped";
    inherit (inner) version meta;

    buildInputs = [ inner ];

    inner = lib.buildInput inner;

    buildCommand = ''
      mkdir -p $out/bin
      for binary in $inner/bin/llvm-*; do
        filename=$(basename $binary)
        [[ ! -L $binary ]] || binary=$(readlink -e $binary)
        ln -s $binary $out/bin/''${filename#llvm-}
      done
    '';
  };

  wrapCargoBinutils = { stdenvNoCC, makeWrapper }: { inner, bintools }: stdenvNoCC.mkDerivation {
    pname = "${inner.pname}-wrapped";
    inherit (inner) version meta;

    nativeBuildInputs = [ makeWrapper ];
    buildInputs = [ inner bintools ];

    inner = lib.buildInput inner;
    bintools = lib.buildInput bintools;

    # $bintools/bin should contain: ar, nm, objcopy, objdump, profdata, readobj/readelf, size, strip, cov
    buildCommand = ''
      mkdir -p $out/bin
      for binary in $inner/bin/*; do
        filename=$(basename $binary)
        if [[ $filename = rust-* ]]; then
          toolname=''${filename#rust-}
          target=$bintools/bin/$toolname
          if [[ $toolname = readobj && -e $bintools/bin/readelf && ! -e $bintools/bin/readobj ]]; then
            target=$bintools/bin/readelf
          fi
          [[ ! -L $target ]] || target=$(readlink -e $target)
          if [[ -e $target ]]; then
            ln -s $target $out/bin/$filename
          elif [[ -e $bintools/bin/llvm-$toolname ]]; then
            ln -s $bintools/bin/llvm-$toolname $out/bin/$filename
          elif [[ $toolname = ld ]] || [[ $toolname = lld ]]; then
            true
          else
            echo "$toolname not found in $bintools" >&2
            exit 1
          fi
        else
          makeWrapper $binary $out/bin/$(basename $binary) --argv0 '$0' \
            --run '[[ -z $CARGO_BUILD_TARGET ]] || set -- --target "$CARGO_BUILD_TARGET" "$@"' \
            --prefix PATH : $out
        fi
      done
    '';
  };

  wrapMiri = { stdenvNoCC, makeWrapper, xargo ? null }: { miri, rust-src, cargo, rustc }: stdenvNoCC.mkDerivation {
    pname = "${miri.pname}-wrapped";
    version = if miri.version or null != null then miri.version else "unknown";

    buildInputs = [ miri rust-src cargo rustc xargo makeWrapper ];

    miri = lib.buildInput miri;
    rustcSrc = lib.buildInput rust-src;
    rustc = lib.buildInput rustc;
    cargo = lib.buildInput cargo;
    xargo = lib.buildInput xargo;

    buildCommand = ''
      mkdir -p $out/bin
      makeWrapper $miri/bin/cargo-miri $out/bin/cargo-miri \
        --set-default XARGO_RUST_SRC "$rustcSrc" \
        --set-default XARGO "$xargo/bin/xargo" \
        --set-default RUSTC "$rustc/bin/rustc" \
        --set-default CARGO "$cargo/bin/cargo" \
        --set-default MIRI_SKIP_SYSROOT_CHECK 1
    '';

    meta = miri.meta or {} // {
      mainProgram = "cargo-miri";
      broken = miri.broken or false || xargo == null;
    };
  };

  makeRustPlatform = {
    makeRustPlatform
  , stdenv, path, lib
  , newScope, buildPackages
  , runCommand
  }: { rust ? null, cargo, rustc, rust-src }: let
    rlib = self;
    platform = lib.makeExtensible (self: makeRustPlatform.override {
      inherit (self) callPackage;
      buildPackages = buildPackages // {
        callPackage = buildPackages.newScope {
          inherit cargo rustc;
        };
      };
    } {
      inherit cargo rustc stdenv;
    });
    patchSetupHook = hook: runCommand hook.name {
      preferLocalBuild = true;
      inherit hook;
      rustTargetPlatformSpec = rust.toRustTargetSpec stdenv.hostPlatform;
      targetName = rlib.rustTargetFor stdenv.hostPlatform;
    } ''
      mkdir $out
      cp --no-preserve=mode -r $hook/* $out/
      sed -i \
        -e "s/--target $rustTargetPlatformSpec//" \
        -e "s|target/$rustTargetPlatformSpec/|target/\\\''${CARGO_BUILD_TARGET_NAME-\\\''${CARGO_BUILD_TARGET-$targetName}}/|" \
        $out/nix-support/setup-hook
    '';
  in platform.extend (self: super: {
    callPackage = newScope {
      rustPlatform = self;
      inherit rust;
      inherit (self.rust) rustc cargo;
      inherit (self)
        buildRustPackage fetchCargoTarball importCargoLock
        cargoBuildHook cargoCheckHook cargoInstallHook cargoSetupHook
        maturinBuildHook bindgenHook
        rustcSrc rustLibSrc
      ;
      ${if lib.versionAtLeast lib.version "23.05" then "cargoNextestHook" else null} = self.cargoNextestHook;
    };
    rustcSrc = rust-src;
    buildRustPackage = rlib.buildRustPackage.override {
      rustPlatform = self;
      buildRustPackage = super.buildRustPackage.override {
        inherit stdenv rust;
        inherit (self)
          fetchCargoTarball
          cargoBuildHook cargoCheckHook cargoInstallHook
          cargoSetupHook
        ;
        ${if lib.versionAtLeast lib.version "23.05" then "cargoNextestHook" else null} = self.cargoNextestHook;
      };
      inherit (self.rust) rustc cargo;
      inherit rust;
      inherit path lib stdenv;
    };
    cargoBuildHook = patchSetupHook super.cargoBuildHook;
    cargoCheckHook = patchSetupHook super.cargoCheckHook;
    cargoInstallHook = patchSetupHook super.cargoInstallHook;
    ${if lib.versionAtLeast lib.version "23.05" then "cargoNextestHook" else null} = patchSetupHook super.cargoNextestHook;
    cargoSetupHook = patchSetupHook super.cargoSetupHook;
    maturinBuildHook = patchSetupHook super.maturinBuildHook;
  });

  makeRust = { newScope, rust, buildPackages }: {
    packages ? {
      inherit (rust.packages) prebuilt;
      stable = builtins.removeAttrs rust.packages.stable [ "newScope" "overrideScope" "overrideScope'" "packages" ];
    },
    buildRust ? buildPackages.rust,
  }: with lib; builtins.removeAttrs rust [ "packages" "override" "overrideDerivation" ] // {
    packages = mapAttrs (channel: packages: lib.makeScope newScope (self: packages // {
      buildRustPackages = buildRust.packages.${channel} or { };
    })) packages;
  };
}
