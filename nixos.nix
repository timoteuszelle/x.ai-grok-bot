{ config, lib, pkgs, ... }:
let
  cfg = config.programs.grok-bot;
in
{
  options.programs.grok-bot = {
    enable = lib.mkEnableOption "xAI Grok Bot";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./pkgs/grok-bot.nix { };
      description = "Grok Bot package to install system-wide.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
