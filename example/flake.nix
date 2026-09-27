{
  description = "Evolve Client - community Evolve Stage 2 launcher, packaged for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
  {
    # Builds the package against a caller-supplied `pkgs`. License policy
    # (e.g. `nixpkgs.config.allowUnfree`) is therefore decided by the
    # consumer, not by this flake. Consumers must opt in to the unfree
    # license themselves, e.g. `inputs.evolved.lib.mkModdedEvolve pkgs`.
    lib.mkModdedEvolve = pkgs:
      let
        version = "0.1.66";

        # Self-extracting installer: a shell header, a "__PAYLOAD__" marker line,
        # then a gzip'd tar archive appended after it.
        #
        # sha256 is a placeholder. Nix will refuse to build until you set the
        # real one, which is the point: once pinned, this exact bytes-for-bytes
        # file is what gets built from now on. Get the real hash with:
        #   nix store prefetch-file --hash-type sha256 \
        #     https://assets.modded-evolve.com/client/linux/ModdedEvolveClient-Setup.run
        # (or: nix-prefetch-url <url>)
        src = pkgs.fetchurl {
          url = "https://assets.modded-evolve.com/client/linux/ModdedEvolveClient-Setup.run";
          sha256 = "sha256-vlXACBxMZ06ko68XYmFQ02YLpT9GA5u9tGTWJc9d2YA=";
        };

        # Shared between buildInputs (so autoPatchelf can fix up real ELF NEEDED
        # entries) and LD_LIBRARY_PATH (so libraries the app instead loads via
        # runtime dlopen/P-Invoke - Avalonia's X11 backend, LibVLCSharp, etc. -
        # can still be found; those never show up as NEEDED so autoPatchelf
        # has no RPATH to fix for them).
        runtimeLibs = with pkgs; [
          stdenv.cc.cc.lib
          zlib
          icu
          openssl
          krb5
          libx11
          libice
          libsm
          fontconfig
          vulkan-loader
          vlc
          libglvnd
        ];
      in
      pkgs.stdenv.mkDerivation {
        pname = "modded-evolve";
        inherit version src;

        nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper pkgs.gnutar pkgs.gzip ];

        buildInputs = runtimeLibs;

        # libcoreclrtraceptprovider.so links against liblttng-ust.so.0 (the old
        # LTTng-UST ABI). nixpkgs' lttng-ust ships a newer soname, so it can
        # never satisfy this exactly - and it doesn't need to: that .so is only
        # used for optional LTTng-based EventPipe tracing, which nothing here
        # enables. Tell autoPatchelf to skip it rather than fail the build.
        autoPatchelfIgnoreMissingDeps = [ "liblttng-ust.so.0" ];

        dontConfigure = true;
        dontBuild = true;

        # Reproduce the installer's own unpack step: find the line after
        # "__PAYLOAD__" and pipe everything from there into tar.
        unpackPhase = ''
          runHook preUnpack
          archiveLine=$(awk '/^__PAYLOAD__$/ { print NR + 1; exit 0; }' "$src")
          tail -n "+$archiveLine" "$src" | tar xz --strip-components=1
          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/opt/modded-evolve"
          cp -r . "$out/opt/modded-evolve/"

          chmod +x "$out/opt/modded-evolve/ModdedEvolveLauncher" \
                   # I think this is unnecessary, we never run SetupLinux.sh but it works this way
                   "$out/opt/modded-evolve/SetupLinux.sh" \
                   "$out/opt/modded-evolve/Compat/Linux/umu/umu-run" 2>/dev/null || true
          find "$out/opt/modded-evolve" -name '*.so' -exec chmod +x {} +

          mkdir -p "$out/bin"
          # steam-run gives the process tree a real FHS environment (via its
          # own bwrap layer). Proton/umu-run's pressure-vessel container also
          # uses bwrap internally and assumes things like /usr/bin/true exist
          # at fixed paths, which plain NixOS doesn't provide - without this,
          # launching the actual game fails with
          # "bwrap: execvp true: No such file or directory".
          makeWrapper "${pkgs.steam-run}/bin/steam-run" "$out/bin/modded-evolve" \
            --add-flags "$out/opt/modded-evolve/ModdedEvolveLauncher" \
            --chdir "$out/opt/modded-evolve" \
            --set DOTNET_SYSTEM_GLOBALIZATION_INVARIANT 1 \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"

          install -Dm444 "$out/opt/modded-evolve/Assets/branding/modded-evolve.png" \
            "$out/share/icons/hicolor/256x256/apps/modded-evolve.png"

          mkdir -p "$out/share/applications"
          cat > "$out/share/applications/modded-evolve.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Evolve Client
Comment=Evolve Stage 2, community servers
Exec=$out/bin/modded-evolve
Icon=modded-evolve
Categories=Game;
Terminal=false
EOF

          runHook postInstall
        '';

        # autoPatchelfHook rewrites RPATH/interpreter on the .NET launcher
        # binary and bundled .so files to point at the Nix store paths above,
        # in place of the system libraries the upstream .run script installs
        # via apt/pacman/dnf.

        meta = with pkgs.lib; {
          description = "Third-party/unofficial community launcher for Evolve Stage 2";
          homepage = "https://assets.modded-evolve.com";
          platforms = [ "x86_64-linux" ];
          license = licenses.unfree; # proprietary game binaries, not open source
          mainProgram = "modded-evolve";
        };
      };
  };
}
