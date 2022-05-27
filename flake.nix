{
  inputs = {
    nixpkgs = {
    };
  };
  outputs = { nixpkgs, self, ... }: let
    forSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed or nixpkgs.lib.systems.supported.hydra;
  in {
    legacyPackages = forSystems (system: import ./default.nix {
      pkgs = nixpkgs.legacyPackages.${system};
    });
    overlays.default = import ./overlay.nix;
    devShells = forSystems (system: {
      default = self.devShells.${system}.latest;
    } // builtins.mapAttrs (_: c: c.mkShell { }) ({
      inherit (self.legacyPackages.${system}) stable beta nightly latest;
    } // self.legacyPackages.${system}.releases));
  };
}
