{
  description = "Rapid serial text presenter";

  outputs = { self, nixpkgs, nimble }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      overlay = final: prev: {
        hottext = prev.hottext.overrideAttrs (attrs: { src = self; });
      };

      defaultPackage = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}.extend self.overlay;
        in pkgs.hottext);
    };
}
