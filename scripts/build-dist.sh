#!/usr/bin/env bash
# Compila artefactos unsigned en dist/<version>/ (Linux + Mono/xbuild).
# Exporta secretos en base64 para GitHub Actions.
# Firma NuGet y publicación completa: scripts/release.ps1 (Windows).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

DEFAULT_SNK="$ROOT/NETFastSearchLibrary/EMZApps.snk"

export_base64() {
  local src="$1"
  local secret_name="$2"
  [[ -f "$src" ]] || { echo "No se encontró: $src" >&2; exit 1; }
  local out="${src}_base64"
  base64 -w0 "$src" > "$out"
  echo "==> Exportado: $out"
  echo "    Secreto GitHub: $secret_name"
  echo "    Copie el contenido (una sola línea) en Environment → release → Secrets."
}

show_help() {
  cat <<EOF
Uso: $SCRIPT_NAME <comando> [argumentos]

Comandos de compilación
  <version>                 Compila Release unsigned → dist/<version>/
                            Ejemplo: $SCRIPT_NAME 1.0.4

Comandos de exportación (base64 → archivo *_base64, gitignored)
  --export-snk-base64 [ruta]
                            EMZApps.snk → <ruta>_base64
                            Secreto: EMZAPPS_SNK
                            Default: $DEFAULT_SNK

  --export-pfx-base64 <ruta.pfx>
                            Certificado Authenticode → <ruta.pfx>_base64
                            Secreto: NUGET_SIGN_CERT_PFX
                            (requiere ruta al .pfx)

Secretos de GitHub (Environment: release)
  EMZAPPS_SNK               Strong-name (.snk en base64) — obligatorio
  NUGET_API_KEY             API key nuget.org — obligatorio
  NUGET_SIGN_CERT_PFX       Certificado Authenticode (.pfx en base64) — opcional
  NUGET_SIGN_CERT_PASSWORD  Contraseña del .pfx — opcional (solo con PFX)

Variables locales (scripts/release.env, no versionar)
  EMZAPPS_SNK_PATH          Ruta al .snk (opcional)
  NUGET_SIGN_CERT_PFX       Ruta al .pfx
  NUGET_SIGN_CERT_PASSWORD  Contraseña del certificado
  NUGET_API_KEY             API key NuGet.org

Plantilla: scripts/release.env.example

Notas
  - Los archivos *_base64 están en .gitignore (no subir al repo).
  - En Windows: .\\scripts\\release.ps1 -ExportSnkBase64
  - Release completo (firmado + NuGet): scripts/release.ps1 en Windows o tag v* → CI.

EOF
}

build_dist() {
  local version="$1"

  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[[:alnum:].]+)?$ ]] || {
    echo "Versión inválida: $version" >&2
    exit 1
  }

  local assembly_info="$ROOT/NETFastSearchLibrary/Properties/AssemblyInfo.cs"
  if [[ -f "$assembly_info" ]]; then
    local info_ver
    info_ver="$(grep -oP 'AssemblyVersion\("\K[0-9]+\.[0-9]+\.[0-9]+' "$assembly_info" || true)"
    if [[ -n "$info_ver" && "$info_ver" != "$version" ]]; then
      echo "AssemblyInfo.cs ($info_ver) no coincide con $version" >&2
      exit 1
    fi
  fi

  command -v xbuild >/dev/null || { echo "xbuild no encontrado (instale Mono)." >&2; exit 1; }

  local dist="$ROOT/dist/$version"
  local project="$ROOT/NETFastSearchLibrary/NETFastSearchLibrary.csproj"

  echo "==> Restaurando paquetes (si existen en packages/)"
  if command -v nuget >/dev/null; then
    nuget restore "$ROOT/NETFastSearchLibrary.sln" || true
  fi

  echo "==> Compilando Release (sin strong-name)"
  xbuild "$project" /p:Configuration=Release /p:Platform=AnyCPU /t:Rebuild /verbosity:minimal

  local release_bin="$ROOT/NETFastSearchLibrary/bin/Release"
  rm -rf "$dist"
  mkdir -p "$dist"

  cp "$release_bin/NETFastSearchLibrary.dll" "$dist/"
  cp "$release_bin/NETFastSearchLibrary.XML" "$dist/" 2>/dev/null || true
  cp "$ROOT/LICENSE" "$dist/"
  cp "$ROOT/README.md" "$dist/"

  echo "==> Listo: $dist"
  ls -la "$dist"
}

# --- Entrada ---
case "${1:-}" in
  -h|--help|help|'')
    show_help
    [[ -n "${1:-}" ]] || exit 0
    ;;
  --export-snk-base64)
    export_base64 "${2:-$DEFAULT_SNK}" "EMZAPPS_SNK"
    ;;
  --export-pfx-base64)
    [[ -n "${2:-}" ]] || {
      echo "Error: indique la ruta al .pfx" >&2
      echo "Ejemplo: $SCRIPT_NAME --export-pfx-base64 /ruta/codigo-firma.pfx" >&2
      exit 1
    }
    export_base64 "$2" "NUGET_SIGN_CERT_PFX"
    ;;
  --export-snk-base64=*)
    export_base64 "${1#*=}" "EMZAPPS_SNK"
    ;;
  --export-pfx-base64=*)
    export_base64 "${1#*=}" "NUGET_SIGN_CERT_PFX"
    ;;
  -*)
    echo "Opción desconocida: $1" >&2
    echo "Use: $SCRIPT_NAME --help" >&2
    exit 1
    ;;
  *)
    build_dist "$1"
    ;;
esac
