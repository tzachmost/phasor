{
  description = "Phasor Shell for MangoWM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mango = {
      url = "github:mangowm/mango";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, mango, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
            backgroundRemovalPython = pkgs.python3.withPackages (ps: [ ps.pillow ps.rembg ]);
        in {
          default = pkgs.callPackage ./package/nix/phasor.nix { };
          preview-ocr = pkgs.buildEnv {
            name = "phasor-preview-ocr";
            paths = [ pkgs.ocrmypdf pkgs.tesseract5 ];
            ignoreCollisions = true;
          };
          preview-background-removal = pkgs.writeShellScriptBin "phasor-preview-bg-python" ''
            exec ${backgroundRemovalPython}/bin/python "$@"
          '';
        });

      nixosModules.default = import ./package/nix/module.nix { inherit self mango; };
    };
}
