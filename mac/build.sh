#!/bin/bash
# Compile Minima Studio et l'installe sur ce Mac (sans publier de mise à jour).
set -e
cd "$(dirname "$0")"
source ./scripts_common.sh
compile_app ""
sign_app
install_locally
echo "✓ Minima Studio est installée."
