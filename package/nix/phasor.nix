{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  findutils,
  gnugrep,
  quickshell,
  poppler-utils,
  python3,
  dejavu_fonts,
  xdg-utils,
  wl-clipboard,
  glib,
  swaybg,
  cliphist,
  swaynotificationcenter,
  flameshot,
  playerctl,
  brightnessctl,
  wireplumber,
  networkmanager,
  bluez,
  polkit_gnome,
}:
let
  previewPython = python3.withPackages (ps: [ ps.pillow ps.pypdf ps.reportlab ps.cryptography ps.pyhanko ]);
in
stdenvNoCC.mkDerivation {
  pname = "phasor-shell";
  version = (builtins.fromTOML (builtins.readFile ../../pyproject.toml)).project.version;
  src = ../..;

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/phasor" "$out/bin" "$out/share/wayland-sessions"
    cp -R "$src/README.md" "$src/AGENTS.md" "$src/LICENSE" \
      "$src/preview.qml" "$src/shell" "$src/plugins" "$src/core" "$src/config" \
      "$src/session" "$src/scripts" "$src/docs" "$out/share/phasor/"
    cp -R "$src/apps" "$out/share/phasor/"

    runtimePath="${lib.makeBinPath [
      bash coreutils findutils gnugrep quickshell previewPython poppler-utils xdg-utils wl-clipboard
      glib swaybg cliphist swaynotificationcenter flameshot playerctl brightnessctl
      wireplumber networkmanager bluez polkit_gnome
    ]}"
    for name in phasorctl phasor-core phasor-doctor; do
      makeWrapper "$out/share/phasor/scripts/$name" "$out/bin/$name" \
        --set PHASOR_HOME "$out/share/phasor" \
        --prefix PATH : "$runtimePath"
    done
    makeWrapper "$out/share/phasor/session/phasor-session" "$out/bin/phasor-session" \
      --set PHASOR_HOME "$out/share/phasor" \
      --prefix PATH : "$runtimePath"
    makeWrapper "$out/share/phasor/scripts/phasor-preview" "$out/bin/phasor-preview" \
      --set PHASOR_PREVIEW_ROOT "$out/share/phasor" \
      --set PHASOR_PREVIEW_FONT "${dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf" \
      --prefix PATH : "$runtimePath"

    mkdir -p "$out/share/applications"
    install -m 644 "$out/share/phasor/apps/preview/phasor-preview.desktop" \
      "$out/share/applications/phasor-preview.desktop"

    substitute "$out/share/phasor/session/phasor.desktop.in" \
      "$out/share/wayland-sessions/phasor.desktop" \
      --replace-fail @PHASOR_SESSION_PATH@ "$out/bin/phasor-session"
    runHook postInstall
  '';

  passthru.providedSessions = [ "phasor" ];

  meta = {
    description = "Portable desktop shell for MangoWM";
    homepage = "https://github.com/tzachmost/phasor";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
