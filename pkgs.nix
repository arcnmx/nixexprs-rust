{ pkgs ? import <nixpkgs> { } }: let
  overlay = import ./overlay.nix;
in if pkgs ? rustChannel then pkgs else pkgs.extend overlay
