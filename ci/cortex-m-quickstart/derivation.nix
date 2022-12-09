{ rustPlatform
, lib
, fetchFromGitHub
, qemu
}: with lib; rustPlatform.buildRustPackage rec {
  pname = "cortex-m-quickstart";
  version = "2019-08-13";
  src = fetchFromGitHub {
    owner = "rust-embedded";
    repo = pname;
    rev = "3ca2bb9a4666dabdd7ca73c6d26eb645cb018734";
    sha256 = "0rf220rsfx10zlczgkfdvhk1gqq2gwlgysn7chd9nrc0jcj5yc7n";
  };

  cargoPatches = [ ./lock.patch ];
  cargoSha256 = "16gmfq6v7qqa2xzshjbgpffygvf7nd5qn31m0b696rnwfj4rxlag";

  buildType = "debug";

  # nixpkgs cross builds force doCheck=false :(
  doCheck = false;
  postBuild = ''
    doCheck=true
  '';

  depsBuildBuild = [ qemu ]; # this should be checkInputs but...
  checkPhase = ''
    sed -i -e 's/# runner = "qemu/runner = "qemu/' .cargo/config
    cargo run -v --example hello
  '';

  meta.platforms = platforms.all;
}
