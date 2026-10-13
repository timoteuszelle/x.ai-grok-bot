{
  description = "Nix-native xAI Grok Bot package and modules (flake + Home Manager + plain NixOS)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: lib.genAttrs systems (system:
        f {
          inherit system;
          # The upstream binary is unfree. Allow it for this flake's own
          # package, app, and devshell outputs. The overlay does not, so a
          # caller that follows their own nixpkgs still opts in themselves.
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        });
    in
    {
      overlays.default = final: _prev: {
        grok-bot = final.callPackage ./pkgs/grok-bot.nix { };
      };

      packages = forAllSystems ({ system, pkgs }: {
        grok-bot = pkgs.callPackage ./pkgs/grok-bot.nix { };
        default = self.packages.${system}.grok-bot;
      });

      apps = forAllSystems ({ system, pkgs }: {
        grok-bot = {
          type = "app";
          program = "${self.packages.${system}.grok-bot}/bin/grok-bot";
        };
        default = self.apps.${system}.grok-bot;
      });

      devShells = forAllSystems ({ system, pkgs }: {
        default = pkgs.mkShell {
          packages = [ self.packages.${system}.grok-bot ];
        };
      });

      nixosModules.default = import ./nixos.nix;
      homeManagerModules.default = import ./home.nix;
      homeModules = self.homeManagerModules;
    };
}
