{ pkgs ? import <nixpkgs> { } }:
pkgs.callPackage ./pkgs/grok-bot.nix { }
