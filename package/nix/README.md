# NixOS

Phasor provides a flake package and NixOS module. Add Phasor to the host flake and import `inputs.phasor.nixosModules.default` from a NixOS module. The module imports Mango's upstream NixOS module, enables MangoWM, adds Quickshell, and registers a separate Phasor Wayland session.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mango = {
      url = "github:mangowm/mango";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    phasor = {
      url = "github:tzachmost/phasor";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.mango.follows = "mango";
    };
  };

  outputs = { nixpkgs, phasor, ... }: {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        phasor.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

Apply the system configuration with `sudo nixos-rebuild switch --flake .#myHost`, then select **Phasor** in the display manager. The package exposes `phasor-doctor`; settings, plugin data and caches stay in the user's XDG directories. Mango and Quickshell versions are pinned by the host's `flake.lock`.

The Preview app is installed separately as `phasor-preview`. To enable its PDF viewer, add `pkgs.qt6.qtwebengine` to `environment.systemPackages`; image viewing works without that package.

Background removal is optional because its CPU inference runtime adds a large closure. To enable it, add `inputs.phasor.packages.${pkgs.system}.preview-background-removal` to `environment.systemPackages`. Preview detects its `phasor-preview-bg-python` command automatically; the model weights download the first time the feature runs.

Local image recognition and searchable PDF export are optional. Add `inputs.phasor.packages.${pkgs.system}.preview-ocr` to `environment.systemPackages` to provide Tesseract and OCRmyPDF; see [Preview's OCR notes](../../docs/preview.md#local-ocr) for language data and behavior.

Update Phasor by updating the host flake lock and rebuilding. Remove the module import and rebuild to uninstall the session package. User settings and data are left in place.
