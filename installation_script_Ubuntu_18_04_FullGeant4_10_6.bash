#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "${SCRIPT_DIR}/installation_script_Ubuntu_FullGeant4_10_6.bash" --expect-ubuntu 18.04 "$@"
