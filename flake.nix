{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia/cachix";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
    };
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, nix-gaming, ... }:
    let
      userName = "laughablehammer";
      mkHost =
        hostName:
        let
          hostPath = ./hosts + "/${hostName}";
        in
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs hostName userName; };
          modules = [
            ./configuration.nix
            hostPath
            { networking.hostName = hostName; }
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs hostName userName; };
              home-manager.users.${userName} = {
                imports = [
                  ./home.nix
                  (hostPath + "/home.nix")
                ];
              };
            }
          ];
        };
    in
    {
      packages.x86_64-linux = {
        inherit (nix-gaming.packages.x86_64-linux) rocket-league;
      };

      nixosConfigurations = {
        hammernix = mkHost "hammernix";
      };
    };
}
