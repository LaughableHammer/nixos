{


  inputs = {
    # Pinned to the revision hyprland.cachix.org builds against, so Hyprland
    # stays prebuilt and mesa stays in lockstep (see hyprland input below).
    nixpkgs.url = "github:nixos/nixpkgs/e554fab72f81915600f3f449b786fd9af40439a5";
    # Separate pin for llama.cpp so its (uncached) ROCm build stays cached and
    # can be bumped independently of the rest of the system.
    nixpkgs-llama.url = "github:NixOS/nixpkgs/7a0f122f5090cf4c2ade2a13a0e229d4e19ba71f";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
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
