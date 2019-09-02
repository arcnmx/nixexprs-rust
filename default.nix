{ pkgs ? import <nixpkgs> { } }:
pkgs.rustChannel or (pkgs.extend (import ./overlay.nix)).rustChannel
