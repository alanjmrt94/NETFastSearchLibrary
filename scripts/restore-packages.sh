#!/usr/bin/env bash
# Restaura paquetes BCL en packages/ sin depender de nuget+Mono SSL.
# nuget restore sobre .sln falla en Linux (MSBUILD0004 + CERTIFICATE_VERIFY_FAILED).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="$ROOT/packages"

declare -A NUGET_PACKAGES=(
  ["Microsoft.Bcl.1.1.10"]="https://www.nuget.org/api/v2/package/Microsoft.Bcl/1.1.10"
  ["Microsoft.Bcl.Async.1.0.168"]="https://www.nuget.org/api/v2/package/Microsoft.Bcl.Async/1.0.168"
  ["Microsoft.Bcl.Build.1.0.21"]="https://www.nuget.org/api/v2/package/Microsoft.Bcl.Build/1.0.21"
)

REQUIRED_MARKERS=(
  "Microsoft.Bcl.Build.1.0.21/build/Microsoft.Bcl.Build.targets"
  "Microsoft.Bcl.1.1.10/lib/net40/System.IO.dll"
  "Microsoft.Bcl.Async.1.0.168/lib/net40/Microsoft.Threading.Tasks.dll"
)

packages_ok() {
  local marker
  for marker in "${REQUIRED_MARKERS[@]}"; do
    [[ -f "$PACKAGES_DIR/$marker" ]] || return 1
  done
  return 0
}

download_package() {
  local folder="$1"
  local url="$2"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/nuget-pkg.XXXXXX.zip")"
  echo "    Descargando $folder ..."
  curl -fsSL "$url" -o "$tmp"
  rm -rf "$PACKAGES_DIR/$folder"
  mkdir -p "$PACKAGES_DIR/$folder"
  unzip -q "$tmp" -d "$PACKAGES_DIR/$folder"
  rm -f "$tmp"
}

restore_all() {
  local folder url
  for folder in "${!NUGET_PACKAGES[@]}"; do
    url="${NUGET_PACKAGES[$folder]}"
    download_package "$folder" "$url"
  done
}

show_help() {
  cat <<EOF
Uso: $(basename "$0") [--force]

Verifica packages/ para NETFastSearchLibrary y descarga con curl si falta algo.
Evita 'nuget restore' (SSL roto en Mono + MSBUILD0004 con xbuild).

EOF
}

main() {
  local force=false
  [[ "${1:-}" == "--force" ]] && force=true
  [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { show_help; exit 0; }

  if [[ "$force" == false ]] && packages_ok; then
    echo "==> Paquetes NuGet OK en packages/"
    return 0
  fi

  command -v curl >/dev/null || { echo "curl requerido." >&2; exit 1; }
  command -v unzip >/dev/null || { echo "unzip requerido." >&2; exit 1; }

  echo "==> Restaurando paquetes BCL en packages/ (curl)"
  mkdir -p "$PACKAGES_DIR"
  restore_all

  if packages_ok; then
    echo "==> Restauración completada."
  else
    echo "Error: paquetes incompletos tras la descarga." >&2
    exit 1
  fi
}

main "$@"
