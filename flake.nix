{
  description = "Headless machine setup: the NixOS module, its starting config, and the headless agent skill";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # NixOS machines follow the tested NixOS channel.
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-nixos";
  };

  outputs = { self, nixpkgs, nixpkgs-nixos, disko }:
    let
      # The template's key is a placeholder the module refuses; the skill
      # puts the user's own key there.
      checkKey = { lib, ... }: {
        headless.sshKeys = lib.mkForce [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMypJnmwSE7hhkQADVWGRLHsEeA6BU2Sj/TxykcHxHcP flake-check" ];
      };
      # The NixOS template's own machine settings, as the skill installs
      # them, built as an example system for each Linux architecture.
      nixosExample = system: nixpkgs-nixos.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          self.nixosModules.headless
          ./skills/headless/assets/nixos/machine.nix
          checkKey
          { nixpkgs.hostPlatform = system; }
        ];
      };
    in
    {
      # The headless layer for a NixOS machine: import it and set `headless.*`.
      nixosModules.headless = ./modules/nixos/headless.nix;
      nixosModules.default = self.nixosModules.headless;

      # The starting configs the skill copies into a folder on your computer.
      templates.nixos = {
        path = ./skills/headless/assets/nixos;
        description = "A headless NixOS machine's config, using the headless module and a disko disk layout";
      };
      templates.default = self.templates.nixos;

      # The template's own settings, built as example systems, so
      # `nix flake check` proves the module and the template evaluate and
      # build. (Macs are set up natively, with no Nix; see
      # skills/headless/scripts/mac.)
      nixosConfigurations.example-x86_64 = nixosExample "x86_64-linux";
      nixosConfigurations.example-aarch64 = nixosExample "aarch64-linux";

      checks.x86_64-linux.example = self.nixosConfigurations.example-x86_64.config.system.build.toplevel;
      checks.aarch64-linux.example = self.nixosConfigurations.example-aarch64.config.system.build.toplevel;
    };
}
