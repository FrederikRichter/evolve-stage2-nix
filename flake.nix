{
  description = "Evolve Stage 2 community launcher";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      mkModdedEvolve = pkgs:
        let
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
        pkgs.stdenv.mkDerivation rec {
          pname = "modded-evolve";
          version = "0.1.67";

          src = pkgs.fetchurl {
            url = "https://assets.modded-evolve.com/client/linux/ModdedEvolveClient-Setup.run";
            hash = "sha256-UquXPINOwqoyH/3tk6hYX4YNM3IANRTAJNKvCeQylXM=";
          };

          nativeBuildInputs = with pkgs; [ autoPatchelfHook makeWrapper ];
          buildInputs = runtimeLibs;

          # libcoreclrtraceptprovider.so links against liblttng-ust.so.0 (old ABI),
          # which is only needed for optional tracing. Skip it.
          autoPatchelfIgnoreMissingDeps = [ "liblttng-ust.so.0" ];

          dontConfigure = true;
          dontBuild = true;

          # Unpack payload following the self-extracting marker
          unpackPhase = ''
            runHook preUnpack
            archiveLine=$(awk '/^__PAYLOAD__$/ { print NR + 1; exit 0; }' "$src")
            tail -n "+$archiveLine" "$src" | tar xz --strip-components=1
            runHook postUnpack
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p "$out/opt/modded-evolve" "$out/bin" "$out/share/applications" "$out/share/icons/hicolor/256x256/apps"
            cp -r . "$out/opt/modded-evolve/"

            chmod +x "$out/opt/modded-evolve/ModdedEvolveLauncher" \
                     "$out/opt/modded-evolve/Compat/Linux/umu/umu-run" 2>/dev/null || true
            find "$out/opt/modded-evolve" -name '*.so' -exec chmod +x {} +

            # Wrap with steam-run to provide an FHS environment for Proton / pressure-vessel
            makeWrapper "${pkgs.steam-run}/bin/steam-run" "$out/bin/modded-evolve" \
              --add-flags "$out/opt/modded-evolve/ModdedEvolveLauncher" \
              --chdir "$out/opt/modded-evolve" \
              --set DOTNET_SYSTEM_GLOBALIZATION_INVARIANT 1 \
              --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath runtimeLibs}"

            install -Dm444 "$out/opt/modded-evolve/Assets/branding/modded-evolve.png" \
              "$out/share/icons/hicolor/256x256/apps/modded-evolve.png"

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

          meta = with pkgs.lib; {
            description = "Community launcher for Evolve Stage 2";
            homepage = "https://modded-evolve.com";
            platforms = [ "x86_64-linux" ];
            license = licenses.unfree;
            mainProgram = "modded-evolve";
          };
        };

      modded-evolve = mkModdedEvolve pkgs;
    in
    {
      packages.${system} = {
        default = modded-evolve;
        modded-evolve = modded-evolve;
      };

      apps.${system}.default = {
        type = "app";
        program = "${modded-evolve}/bin/modded-evolve";
      };

      overlays.default = final: prev: {
        modded-evolve = mkModdedEvolve final;
      };

      lib.mkModdedEvolve = mkModdedEvolve;
    };
}
