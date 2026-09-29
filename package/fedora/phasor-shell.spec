Name:           phasor-shell
Version:        @PHASOR_VERSION@
Release:        1%{?dist}
Summary:        Portable desktop shell for MangoWM
License:        MIT
URL:            https://github.com/tzachmost/phasor
Source0:        phasor-%{version}.tar.gz
BuildArch:      noarch

Requires:       mangowm
Requires:       quickshell
Requires:       python3
Requires:       python3-pillow
Requires:       python3-pypdf
Requires:       python3-reportlab
Requires:       dejavu-sans-fonts
Requires:       libwebp
Requires:       xdg-utils
Requires:       wl-clipboard
Requires:       glib2
Requires:       swaybg
Requires:       cliphist
Requires:       SwayNotificationCenter
Requires:       flameshot
Recommends:     playerctl
Recommends:     brightnessctl
Recommends:     wireplumber
Recommends:     NetworkManager
Recommends:     bluez
Recommends:     polkit-gnome
Suggests:       qt6-qtpdf

%description
Phasor is a portable MangoWM desktop shell with a Quickshell UI, app and file
launcher, settings, a bar, optional dock, desktop shortcuts and service adapters.

%prep
%autosetup -n phasor-%{version}

%build

%install
mkdir -p %{buildroot}%{_datadir}/phasor
cp -a README.md LICENSE AGENTS.md preview.qml shell plugins apps core config session scripts docs %{buildroot}%{_datadir}/phasor/
mkdir -p %{buildroot}%{_bindir} %{buildroot}%{_datadir}/wayland-sessions
ln -s ../share/phasor/scripts/phasorctl %{buildroot}%{_bindir}/phasorctl
ln -s ../share/phasor/scripts/phasor-core %{buildroot}%{_bindir}/phasor-core
ln -s ../share/phasor/scripts/phasor-doctor %{buildroot}%{_bindir}/phasor-doctor
ln -s ../share/phasor/scripts/phasor-preview %{buildroot}%{_bindir}/phasor-preview
ln -s ../share/phasor/session/phasor-session %{buildroot}%{_bindir}/phasor-session
mkdir -p %{buildroot}%{_datadir}/applications
install -m 644 apps/preview/phasor-preview.desktop %{buildroot}%{_datadir}/applications/phasor-preview.desktop
sed 's|@PHASOR_SESSION_PATH@|%{_bindir}/phasor-session|g' \
  session/phasor.desktop.in > %{buildroot}%{_datadir}/wayland-sessions/phasor.desktop

%files
%license LICENSE
%doc README.md
%{_datadir}/phasor
%{_bindir}/phasorctl
%{_bindir}/phasor-core
%{_bindir}/phasor-doctor
%{_bindir}/phasor-preview
%{_bindir}/phasor-session
%{_datadir}/applications/phasor-preview.desktop
%{_datadir}/wayland-sessions/phasor.desktop

%changelog
* Tue Sep 29 2026 Phasor Contributors <maintainers@phasor.dev> - 1.0.0-1
- Prepare the Phasor 1.0 release for Fedora and Universal Blue
