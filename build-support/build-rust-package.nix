{ path, lib
, rustChannel, buildRustPackage ? rustChannel.buildRustPackage
, rust ? null, rustPlatform
, stdenv
, cargo, windows ? null
, rustc
}: let
  buildRustPackage' = buildRustPackage.override {
    callPackage = _: _: throw "no sysroot for you";
  };
  fn = if builtins.pathExists (path + "/pkgs/build-support/rust/hooks/cargo-build-hook.sh")
    then new
    else old;
  new = {
    rustTarget ? rustChannel.lib.rustTargetFor stdenv.hostPlatform
  , ...
  }@args: (buildRustPackage' ({
  } // builtins.removeAttrs args [ "rustTarget" ])).overrideAttrs (old: {
    ${if args ? rustTarget then "CARGO_BUILD_TARGET" else null} = rustTarget;
    ${if lib.hasSuffix ".json" rustTarget then "CARGO_BUILD_TARGET_NAME" else null} = lib.removeSuffix ".json" (builtins.baseNameOf rustTarget);
    ${if args ? RUSTFLAGS then "RUSTFLAGS" else null} = args.RUSTFLAGS;
  });
old = {
  name ? "${args.pname}-${args.version}"
, cargoSha256 ? lib.fakeSha256
, src ? null
, srcs ? null
, unpackPhase ? null
, cargoPatches ? []
, patches ? []
, sourceRoot ? null
, logLevel ? ""
, buildInputs ? []
, nativeBuildInputs ? []
, cargoUpdateHook ? ""
, cargoDepsHook ? ""
, cargoBuildFlags ? []
, buildType ? "release"
, rustTarget ? rustChannel.lib.rustTargetFor stdenv.hostPlatform
, cargoVendorDir ? null
, ... }@args: let
  cargoDeps = if cargoVendorDir == null
    then rustPlatform.fetchCargoTarball {
      inherit name src srcs sourceRoot unpackPhase cargoUpdateHook;
      patches = cargoPatches;
      sha256 = cargoSha256;
    } else null;
  setupVendorDir = if cargoVendorDir == null
    then ''
      unpackFile $cargoDeps
      cargoDepsCopy=$(stripHash $cargoDeps)
      chmod -R +w $cargoDepsCopy
    '' else ''
      cargoDepsCopy="$sourceRoot/$cargoVendorDir"
    '';
  patchRegistryDeps = path + "/pkgs/build-support/rust/patch-registry-deps";
in lib.drvRec (drv: stdenv.mkDerivation (lib.recursiveUpdate args {
  nativeBuildInputs = [ cargo rustc ] ++ nativeBuildInputs;
  buildInputs = buildInputs ++ lib.optional stdenv.hostPlatform.isMinGW windows.pthreads;
  inherit cargoDeps;

  patches = cargoPatches ++ patches;

  PKG_CONFIG_ALLOW_CROSS =
    if stdenv.buildPlatform != stdenv.hostPlatform then 1 else 0;
  CARGO_TARGET_DIR = "target/cargo";
  releaseDir = "${drv.CARGO_TARGET_DIR}/${rustTarget}/${buildType}";

  inherit cargoDepsHook setupVendorDir;
  #postUnpackHooks =
  #  lib.optional (cargoDepsHook != "") "cargoDepsHook"
  #  ++ [ "setupVendorDir" ];
  postUnpack = ''
    eval "$cargoDepsHook"
    eval "$setupVendorDir"

    mkdir .cargo
    config="$(pwd)/$cargoDepsCopy/.cargo/config"
    if [[ ! -e $config ]]; then
      config=${path + "/pkgs/build-support/rust/fetchcargo-default-config.toml"}
    fi
    substitute $config .cargo/config \
      --subst-var-by vendor "$(pwd)/$cargoDepsCopy"
  '';


  configurePhase = args.configurePhase or ''
    runHook preConfigure

    export RUST_LOG=$logLevel

    mkdir -p .cargo
    cat >> .cargo/config <<EOF
    # TODO
    EOF
    cat .cargo/config

    if [[ -n $CARGO_TARGET_DIR && $CARGO_TARGET_DIR != /* ]]; then
      # canonicalized path
      export CARGO_TARGET_DIR=$NIX_BUILD_TOP/$sourceRoot/$CARGO_TARGET_DIR
    fi

    if [[ ! -e target/$buildType ]]; then
      mkdir -p target
      ln -sr $releaseDir target/$buildType
    fi

    runHook postConfigure
  '';

  buildPhase = args.buildPhase or ''
    runHook preBuild

    cargo build \
      --frozen --verbose \
      $cargoBuildFlags \
      ${lib.optionalString (buildType != "debug") "--${buildType}"} \
      ${lib.optionalString (args ? rustTarget) "--target ${rustTarget}"}

    runHook postBuild
  '';

  checkPhase = args.checkPhase or ''
    runHook preCheck
    echo "Running cargo test"
    cargo test
    runHook postCheck
  '';

  doCheck = args.doCheck or true;

  installPhase = args.installPhase or ''
    runHook preInstall
    mkdir -p $out/bin $out/lib

    find $releaseDir \
      -maxdepth 1 \
      -type f \
      -executable ! \( -regex ".*\.\(so.[0-9.]+\|so\|a\|dylib\|dll\)" \) \
      -print0 | xargs -r -0 cp -t $out/bin
    find $releaseDir \
      -maxdepth 1 \
      -regex ".*\.\(so.[0-9.]+\|so\|a\|dylib\|dll\)" \
      -print0 | xargs -r -0 cp -t $out/lib

    rmdir --ignore-fail-on-non-empty $out/lib $out/bin

    runHook postInstall
  '';
  passthru = {
    #inherit (drv) cargoDeps;
    #inherit rustChannel;
  } // args.passthru or { };
}));
in fn
