{
  description = "Predicta dev environment (Flutter + Python + Docker tooling)";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        python = pkgs.python311;
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          # La app usa API 36; algunos plugins Flutter todavía compilan módulos
          # auxiliares contra 34/35 y Gradle no puede descargarlos en /nix/store.
          platformVersions = [ "34" "35" "36" ];
          # Flutter compila contra API 36, mientras AGP todavía solicita
          # Build Tools 35 como versión predeterminada durante el build.
          buildToolsVersions = [ "34.0.0" "35.0.0" "36.0.0" ];
          includeCmake = true;
          cmakeVersions = [ "3.22.1" ];
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
        };
        # Flutter expects cmdline-tools under the conventional `latest` name,
        # while androidenv keeps the tools under their versioned directory.
        androidSdk = pkgs.runCommand "predicta-android-sdk" {
          nativeBuildInputs = [ pkgs.xorg.lndir ];
        } ''
          mkdir -p "$out/libexec/android-sdk"
          lndir "${androidComposition.androidsdk}/libexec/android-sdk" "$out/libexec/android-sdk"
          ln -s 20.0 "$out/libexec/android-sdk/cmdline-tools/latest"
        '';
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Flutter / Dart toolchain
            flutter
            dart

            # Android-related utilities commonly used by Flutter
            jdk17
            gradle
            androidSdk

            # Linux desktop build deps for Flutter
            clang
            cmake
            ninja
            pkg-config
            gtk3

            # Backend / scripting
            python
            python311Packages.pip
            python311Packages.virtualenv

            # Infra / DX tooling
            docker
            docker-compose
            mariadb
            git
            curl
            jq
          ];

          ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
          JAVA_HOME = "${pkgs.jdk17.home}";

          shellHook = ''
            export PIP_DISABLE_PIP_VERSION_CHECK=1
            export PYTHONDONTWRITEBYTECODE=1
            export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"
            flutter config --android-sdk "$ANDROID_SDK_ROOT" >/dev/null
            flutter config --jdk-dir "$JAVA_HOME" >/dev/null

            echo ""
            echo "Predicta dev shell ready"
            echo "- Flutter: $(flutter --version | head -n 1)"
            echo "- Python:  $(python --version 2>&1)"
            echo "- Android: $ANDROID_SDK_ROOT"
            echo ""
            echo "Useful commands:"
            echo "  docker compose up -d"
            echo "  cd mantenimiento_predictivo && flutter pub get && flutter run"
            echo ""
          '';
        };
      });
}
