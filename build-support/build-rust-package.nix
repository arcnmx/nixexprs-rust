{ path, lib, rustChannel, stdenv, cacert, git, cargo, rustc, fetchcargo }: {
  name ? "${args.pname}-${args.version}"
, cargoSha256 ? lib.fakeSha256
, src ? null
, srcs ? null
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
, cargoVendorDir ? null
, ... }@args: let
  cargoDeps = if cargoVendorDir == null
    then fetchcargo {
      inherit name src srcs sourceRoot cargoUpdateHook;
      patches = cargoPatches;
      sha256 = cargoSha256;
    } else null;
  setupVendorDir = if cargoVendorDir == null
    then ''
      unpackFile $cargoDeps
      cargoDepsCopy=$(stripHash $(basename $cargoDeps))
      chmod -R +w $cargoDepsCopy
    '' else ''
      cargoDepsCopy="$sourceRoot/$cargoVendorDir"
    '';
in lib.drvRec (drv: stdenv.mkDerivation (lib.recursiveUpdate args {
  patchRegistryDeps = path + "/pkgs/build-support/rust/patch-registry-deps";
  nativeBuildInputs = [ cargoDeps cargo rustc git cacert ] ++ nativeBuildInputs;
  inherit buildInputs;
  cargoDeps = lib.findInput drv.nativeBuildInputs cargoDeps;

  patches = cargoPatches ++ patches;

  PKG_CONFIG_ALLOW_CROSS =
    if stdenv.buildPlatform != stdenv.hostPlatform then 1 else 0;
  CARGO_TARGET_DIR = "target/cargo";
  releaseDir = "${drv.CARGO_TARGET_DIR}/${rustChannel.lib.rustTargetFor stdenv.hostPlatform}/${buildType}";

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
      ${lib.optionalString (buildType != "debug") "--${buildType}"}

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
    inherit (drv) cargoDeps;
    #inherit rustChannel;
  } // args.passthru or { };
}))
