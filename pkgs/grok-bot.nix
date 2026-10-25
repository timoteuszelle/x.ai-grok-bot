{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, makeShellWrapper
, wrapGAppsHook3
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, dbus
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, libGL
, libappindicator-gtk3
, libdrm
, libgbm
, libglvnd
, libnotify
, libpulseaudio
, libsecret
, libuuid
, libxkbcommon
, nspr
, nss
, pango
, systemd
, vulkan-loader
, wayland
, xdg-utils
, libx11
, libxcb
, libxcomposite
, libxcursor
, libxdamage
, libxext
, libxfixes
, libxi
, libxrandr
, libxrender
, libxscrnsaver
, libxshmfence
, libxtst
}:
let
  # Pinned from the stable download manifest:
  # https://api2.cursor.sh/updates/api/download/stable/linux-x64/sand
  # https://api2.cursor.sh/updates/api/download/stable/linux-arm64/sand
  version = "0.75.8";
  commit = "039d88c52f45f8af72fbe7379bc426c171edf62b";
  artifacts = {
    x86_64-linux = {
      url = "https://downloads.cursor.com/grokbot/stable/039d88c52f45f8af72fbe7379bc426c171edf62b/linux/x64/grok-bot_0.75.8_amd64.deb";
      hash = "sha256-Q0ZdsVih2dYYqe+caKrqBj3jQjRG+vdiq+fuSP99Jrs=";
    };
    aarch64-linux = {
      url = "https://downloads.cursor.com/grokbot/stable/039d88c52f45f8af72fbe7379bc426c171edf62b/linux/arm64/grok-bot_0.75.8_arm64.deb";
      hash = "sha256-SpnDVP2r5z74soHfaudqgY/Ve8xhXexVOUuvabKLeKI=";
    };
  };
  artifact =
    artifacts.${stdenv.hostPlatform.system}
      or (throw "grok-bot: unsupported system ${stdenv.hostPlatform.system}. Add an artifact entry in pkgs/grok-bot.nix.");

  # Chromium dlopen()s these instead of linking them, so autoPatchelf cannot see them.
  runtimeLibs = [
    libGL
    libappindicator-gtk3
    libdrm
    libgbm
    libglvnd
    libnotify
    libpulseaudio
    libsecret
    libxkbcommon
    vulkan-loader
    wayland
    (lib.getLib systemd)
  ];
in
stdenv.mkDerivation {
  pname = "grok-bot";
  inherit version;

  src = fetchurl {
    inherit (artifact) url hash;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeShellWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libuuid
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
  ] ++ runtimeLibs;

  runtimeDependencies = runtimeLibs;

  dontConfigure = true;
  dontBuild = true;
  # Prebuilt Electron. Stripping is slow and does not help.
  dontStrip = true;
  # The launcher is wrapped by hand so GApps arguments land on our wrapper.
  dontWrapGApps = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/grok-bot"
    cp -a "opt/Grok Bot/." "$out/lib/grok-bot/"

    # chrome-sandbox only works setuid root, which the Nix store cannot express.
    # The NixOS kernel allows user namespaces, so Chromium's sandbox still runs.
    rm -f "$out/lib/grok-bot/chrome-sandbox"

    # The bundled Vulkan loader looks up ICDs in FHS paths.
    if [ -e "$out/lib/grok-bot/libvulkan.so.1" ]; then
      rm -f "$out/lib/grok-bot/libvulkan.so.1"
      ln -s "${lib.getLib vulkan-loader}/lib/libvulkan.so.1" "$out/lib/grok-bot/libvulkan.so.1"
    fi

    found_icon=
    for icon in usr/share/icons/hicolor/*/apps/*; do
      [ -f "$icon" ] || continue
      relative="''${icon#usr/share/icons/hicolor/}"
      size="''${relative%%/*}"
      name="$(basename "$icon")"
      case "$name" in
        sand.*) name="grok-bot.''${name##*.}" ;;
      esac
      install -Dm644 "$icon" "$out/share/icons/hicolor/$size/apps/$name"
      found_icon=1
    done
    if [ -z "$found_icon" ]; then
      echo "grok-bot: no hicolor icon in the .deb" >&2
      exit 1
    fi

    if [ -f usr/share/applications/grok-bot.desktop ]; then
      desktop=usr/share/applications/grok-bot.desktop
    elif [ -f usr/share/applications/sand.desktop ]; then
      desktop=usr/share/applications/sand.desktop
    else
      echo "grok-bot: no desktop file in the .deb" >&2
      exit 1
    fi
    install -Dm644 "$desktop" "$out/share/applications/grok-bot.desktop"
    sed -i \
      -e "s|^Exec=.*|Exec=$out/bin/grok-bot %U|" \
      -e "s|^Icon=.*|Icon=grok-bot|" \
      "$out/share/applications/grok-bot.desktop"

    runHook postInstall
  '';

  preFixup = ''
    if [ -x "$out/lib/grok-bot/grok-bot" ]; then
      upstream_executable="$out/lib/grok-bot/grok-bot"
    elif [ -x "$out/lib/grok-bot/sand" ]; then
      upstream_executable="$out/lib/grok-bot/sand"
    else
      echo "grok-bot: no launcher binary in the .deb" >&2
      exit 1
    fi

    # makeShellWrapper, not the binary wrapper from wrapGAppsHook3. A binary
    # wrapper would pass the ozone parameter expansion through as a literal
    # argument, which Electron treats as a link to open.
    #
    # CHROME_DESKTOP is what Electron registers with xdg-settings for the
    # grokbot:// and sand:// handlers advertised by the desktop file.
    makeShellWrapper "$upstream_executable" "$out/bin/grok-bot" \
      "''${gappsWrapperArgs[@]}" \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --set-default CHROME_DESKTOP grok-bot.desktop \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-wayland-ime=true}}"

    ln -s grok-bot "$out/bin/sand"
  '';

  passthru = {
    inherit commit artifacts;
  };

  meta = {
    description = "xAI Grok Bot desktop agent packaged for Nix/NixOS";
    homepage = "https://x.ai/bot";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames artifacts;
    mainProgram = "grok-bot";
    maintainers = [ ];
  };
}
