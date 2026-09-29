{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  findutils,
  gnugrep,
  quickshell,
  python3,
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
      "$src/shell" "$src/plugins" "$src/core" "$src/config" \
      "$src/session" "$src/scripts" "$src/docs" "$out/share/phasor/"

    runtimePath="${lib.makeBinPath [
      bash coreutils findutils gnugrep quickshell python3 xdg-utils wl-clipboard
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
