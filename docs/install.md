# Installation and updates

Phasor installs as a separate MangoWM login session. The package installs the session and Phasor files; it does not replace a user's Mango configuration. User settings, plugin data, and caches live in XDG directories and remain after uninstall.

The published 1.0.0 packages contain the shell. Preview is part of the 1.1.0 development branch and is installed by source checkouts and development packages.

## Arch Linux and CachyOS

For a source checkout, the installer installs dependencies, adds development links, installs the managed session, and runs diagnostics:

```bash
mkdir -p ~/Work
git clone https://github.com/tzachmost/phasor.git ~/Work/phasor
cd ~/Work/phasor
./scripts/install
```

Update the checkout and the system runtime after reviewing local changes:

```bash
cd ~/Work/phasor
git pull --ff-only
./scripts/install-dev
sudo ./scripts/install-system
./scripts/doctor
```

To build and install the stable Arch release package, first run `./scripts/install-deps` to install MangoWM and the runtime dependencies, then run `makepkg -si` from `package/arch/`. The recipe downloads the matching versioned source archive. To update a package built from this checkout, pull the checkout and rebuild it:

```bash
cd ~/Work/phasor
git pull --ff-only
cd package/arch
makepkg -si
phasor-doctor
```

Once the stable recipe is available from the AUR, packages installed from there can be updated with an AUR helper such as `paru -Syu phasor-shell`. Remove it with `sudo pacman -R phasor-shell`.

Preview is installed as a separate app. Open it from the application launcher or run `phasor-preview path/to/file`. PDF viewing needs the optional `qt6-webengine` package; image viewing and export work without it. The package includes image/PDF export support. Editable image and PDF markup, plus PDF page operations, are stored beside the original as a `*.phasor-markup.json` file.

The main-branch development recipe is kept in `package/arch/PKGBUILD.git`. Build it with `makepkg -si -p PKGBUILD.git`, update it from a newer commit, and remove it with `sudo pacman -R phasor-shell-git`. The stable and development packages replace each other.

## Fedora Workstation

The source installer configures the Terra repository for MangoWM and the Quickshell COPR, installs runtime packages, sets up the Phasor session, and runs diagnostics. Those repository choices follow the [Mango Fedora install guide](https://github.com/mangowm/mango/wiki/installation) and [Quickshell Fedora guide](https://quickshell.org/docs/v0.3.0/guide/install-setup/):

```bash
git clone https://github.com/tzachmost/phasor.git ~/Work/phasor
cd ~/Work/phasor
./scripts/install
```

For source updates, use the Arch/CachyOS update steps above. To build an RPM, install `rpm-build` and run `./scripts/build-rpm`. The RPM and SRPM are written under `package/fedora/RPMS/`. Install or update the exact noarch RPM from that directory with `sudo dnf install /path/to/phasor-shell.rpm`; run `phasor-doctor` after installing. Remove an RPM install with `sudo dnf remove phasor-shell`.

Preview is installed as a separate app. Install `qt6-qtpdf` to enable PDF viewing; image viewing and image export work without that optional package. The RPM includes Pillow, pypdf, ReportLab, and DejaVu Sans for export.

## Universal Blue and other OSTree Fedora systems

Build the Phasor RPM on a Fedora build host using `./scripts/build-rpm`, then copy the noarch RPM to the target. The installer enables Terra and the Quickshell COPR, stages Phasor and `terra-release`, and reports that a reboot is needed. The Terra repo setup follows [Terra's atomic Fedora instructions](https://github.com/terrapkg/packages/blob/frawhide/README.md); the RPM is staged using the [rpm-ostree package layering workflow](https://github.com/ublue-os/docs.bazzite.gg/blob/main/src/Installing_and_Managing_Software/rpm-ostree.md):

```bash
./scripts/install --ostree-rpm /path/to/phasor-shell.rpm
```

The repository files are kept under `/etc/yum.repos.d/phasor-terra.repo` and `/etc/yum.repos.d/phasor-quickshell-copr.repo` so rpm-ostree can resolve MangoWM and Quickshell. Run `phasor-doctor` after reboot. Update a local RPM install together with the next OS update using:

```bash
sudo rpm-ostree upgrade --install=/path/to/phasor-shell-new.rpm --uninstall=phasor-shell
```

Reboot to apply the staged deployment. To uninstall, run `sudo rpm-ostree uninstall phasor-shell` and reboot. Repository files are system configuration and can be removed manually if no other package uses those repositories.

## NixOS

Add the Mango and Phasor inputs and import `inputs.phasor.nixosModules.default` in the host configuration. The module imports the [Mango NixOS module](https://github.com/mangowm/mango/wiki/installation) and registers Phasor as a separate session. The complete flake example is in [package/nix/README.md](../package/nix/README.md). Apply it with `sudo nixos-rebuild switch --flake .#myHost`, then choose **Phasor** in the login manager. Run `phasor-doctor` from a terminal to inspect the session dependencies.

Preview is installed as a separate app. Add `pkgs.qt6.qtwebengine` to the host's packages to enable PDF viewing; image viewing and export support are included in the Phasor package.

Update the Phasor input and switch to the new system generation:

```bash
nix flake lock --update-input phasor
sudo nixos-rebuild switch --flake .#myHost
```

To uninstall, remove the Phasor module import and input from the host flake and rebuild. Settings and user data stay in the XDG directories.

## Development links and uninstall

`./scripts/install-dev` creates user-local command links and a user-local session entry. `./scripts/uninstall` removes those Phasor development links. A source installation that also used `install-system` needs `sudo ./scripts/uninstall --system` to remove the managed system runtime and login entry. These commands refuse unmanaged paths. Package-managed installs should be removed through their package manager.
