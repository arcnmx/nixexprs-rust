{ self, buildSelf, targetSelf, super, pkgs, lib }@args: {
  buildLib = buildSelf;
  targetLib = targetSelf;
  buildRustPackage = pkgs.callPackage ./build-rust-package.nix { };
} // import ./dist.nix args
// import ./target.nix args
// import ./channel.nix args
// import ./crates.nix args
// import ./shell.nix args
