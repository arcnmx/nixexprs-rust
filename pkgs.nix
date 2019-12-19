{ pkgs ? import <nixpkgs> { } }: let
  overlay = import ./overlay.nix;
in if pkgs.rustChannel.path or null == ./.
  then pkgs
  else pkgs.extend overlay
