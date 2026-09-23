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
          config.allowUnfree = true;
        };

        python = pkgs.python311;
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Flutter / Dart toolchain
            flutter
            dart

            # Android-related utilities commonly used by Flutter
            jdk17
            gradle
            android-tools

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

          shellHook = ''
            export PIP_DISABLE_PIP_VERSION_CHECK=1
            export PYTHONDONTWRITEBYTECODE=1

            echo ""
            echo "Predicta dev shell ready"
            echo "- Flutter: $(flutter --version | head -n 1)"
            echo "- Python:  $(python --version 2>&1)"
            echo ""
            echo "Useful commands:"
            echo "  docker compose up -d"
            echo "  cd mantenimiento_predictivo && flutter pub get && flutter run"
            echo ""
          '';
        };
      });
}
