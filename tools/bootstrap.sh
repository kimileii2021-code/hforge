#!/usr/bin/env bash
set -euo pipefail

hforge_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hforge_action="${1:-check}"
if [[ $# -gt 0 ]]; then shift; fi
if [[ "$hforge_action" != check && "$hforge_action" != install ]]; then
  printf '%s\n' '{"ready":false,"agent_action_required":"Unknown bootstrap action"}'
  exit 2
fi
hforge_data="${XDG_DATA_HOME:-$HOME/.local/share}/hforge"
hforge_python=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' >/dev/null 2>&1; then
    hforge_python="$(command -v "$candidate")"
    break
  fi
done
if [[ -z "$hforge_python" && "$hforge_action" == check ]]; then
  printf '%s\n' '{"ready":false,"configuration_plan":["Managed Python 3.11","Then check tools required by the requested stages"],"agent_runs_installation":true,"manual_commands_required":false}'
  exit 1
fi
if [[ -z "$hforge_python" ]]; then
  case "$(uname -s)" in
    Darwin) hforge_os=apple-darwin ;;
    Linux) hforge_os=unknown-linux-gnu ;;
    *) printf '%s\n' '{"ready":false,"agent_action_required":"Use the native Windows bootstrap on Windows"}'; exit 2 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) hforge_arch=aarch64 ;;
    x86_64|amd64) hforge_arch=x86_64 ;;
    *) printf '%s\n' '{"ready":false,"agent_action_required":"Agent must select an installer for this CPU architecture"}'; exit 2 ;;
  esac
  hforge_uv_version=0.13.5
  hforge_asset="uv-${hforge_arch}-${hforge_os}.tar.gz"
  hforge_url="https://github.com/astral-sh/uv/releases/download/${hforge_uv_version}/${hforge_asset}"
  mkdir -p "$hforge_data/downloads" "$hforge_data/tools/uv/$hforge_uv_version"
  curl --fail --location --proto '=https' --tlsv1.2 "$hforge_url.sha256" --output "$hforge_data/downloads/$hforge_asset.sha256"
  curl --fail --location --proto '=https' --tlsv1.2 "$hforge_url" --output "$hforge_data/downloads/$hforge_asset"
  hforge_expected="$(awk '{print $1}' "$hforge_data/downloads/$hforge_asset.sha256")"
  if command -v sha256sum >/dev/null 2>&1; then
    hforge_actual="$(sha256sum "$hforge_data/downloads/$hforge_asset" | awk '{print $1}')"
  else
    hforge_actual="$(shasum -a 256 "$hforge_data/downloads/$hforge_asset" | awk '{print $1}')"
  fi
  if [[ ! "$hforge_expected" =~ ^[a-fA-F0-9]{64}$ || "$hforge_actual" != "$hforge_expected" ]]; then
    printf '%s\n' '{"ready":false,"agent_action_required":"uv checksum mismatch; nothing was executed"}'
    exit 2
  fi
  if tar -tzf "$hforge_data/downloads/$hforge_asset" | grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null; then
    printf '%s\n' '{"ready":false,"agent_action_required":"Unsafe archive path"}'
    exit 2
  fi
  tar -xzf "$hforge_data/downloads/$hforge_asset" -C "$hforge_data/tools/uv/$hforge_uv_version"
  hforge_uv="$(find "$hforge_data/tools/uv/$hforge_uv_version" -type f -name uv -print -quit)"
  export UV_PYTHON_INSTALL_DIR="$hforge_data/python"
  export UV_PYTHON_BIN_DIR="$hforge_data/python-bin"
  export UV_NO_MODIFY_PATH=1
  "$hforge_uv" python install 3.11
  hforge_python="$("$hforge_uv" python find --managed-python 3.11)"
fi
exec "$hforge_python" -X utf8 -B "$hforge_script_dir/bootstrap_environment.py" "$hforge_action" "$@"
