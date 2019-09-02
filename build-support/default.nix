{ self, buildSelf, super, pkgs, lib }@args: {
  buildRustPackage = pkgs.callPackage ./build-rust-package.nix { };
} // import ./dist.nix args
// import ./target.nix args
// import ./channel.nix args
