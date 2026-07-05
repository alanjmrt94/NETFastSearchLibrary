#!/usr/bin/env bash
# Menú interactivo y CLI para compilar, empaquetar y publicar NETFastSearchLibrary.Legacy.
# Linux + Mono (msbuild o xbuild). Release completo en Windows: scripts/release.ps1
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Herramienta de compilación detectada (se rellena en detect_build_tool)
BUILD_TOOL=()
BUILD_TOOL_NAME=""
BUILD_XBUILD_FALLBACK=false
BUILD_HINT_SHOWN=false

DEFAULT_SNK="$ROOT/NETFastSearchLibrary/EMZApps.snk"
ENV_FILE="$SCRIPT_DIR/release.env"
PROJECT="$ROOT/NETFastSearchLibrary/NETFastSearchLibrary.csproj"
NUSPEC="$ROOT/NETFastSearchLibrary/NETFastSearchLibrary.Legacy.nuspec"
SOLUTION="$ROOT/NETFastSearchLibrary.sln"
ASSEMBLY_INFO="$ROOT/NETFastSearchLibrary/Properties/AssemblyInfo.cs"
GITHUB_REPO="${GITHUB_REPO:-alanjmrt94/NETFastSearchLibrary}"

# --- Utilidades ---

load_env() {
  EMZAPPS_SNK_PATH="${EMZAPPS_SNK_PATH:-$DEFAULT_SNK}"
  if [[ -f "$ENV_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line//$'\r'/}"
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
      fi
    done < "$ENV_FILE"
    EMZAPPS_SNK_PATH="${EMZAPPS_SNK_PATH:-$DEFAULT_SNK}"
  fi
}

get_assembly_version() {
  grep -oP 'AssemblyVersion\("\K[0-9]+\.[0-9]+\.[0-9]+' "$ASSEMBLY_INFO" 2>/dev/null || true
}

validate_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[[:alnum:].]+)?$ ]] || {
    echo "Versión inválida: $version" >&2
    return 1
  }
  local info_ver
  info_ver="$(get_assembly_version)"
  if [[ -n "$info_ver" && "$info_ver" != "$version" ]]; then
    echo "AssemblyInfo.cs ($info_ver) no coincide con $version" >&2
    return 1
  fi
}

confirm() {
  local prompt="$1"
  read -r -p "$prompt [s/N]: " reply
  [[ "$reply" =~ ^[sSyY]$ ]]
}

check_git_clean() {
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    local status
    status="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
    if [[ -n "$status" ]]; then
      echo "Advertencia: hay cambios sin commit en el repositorio." >&2
      return 1
    fi
  fi
  return 0
}

snk_available() {
  [[ -f "${EMZAPPS_SNK_PATH:-$DEFAULT_SNK}" ]]
}

export_base64() {
  local src="$1"
  local secret_name="$2"
  [[ -f "$src" ]] || { echo "No se encontró: $src" >&2; return 1; }
  local out="${src}_base64"
  base64 -w0 "$src" > "$out"
  echo "==> Exportado: $out"
  echo "    Secreto GitHub: $secret_name"
  echo "    Copie el contenido (una sola línea) en Environment → release → Secrets."
}

restore_packages() {
  local restore_script="$SCRIPT_DIR/restore-packages.sh"
  if [[ -x "$restore_script" ]]; then
    "$restore_script"
  elif [[ -f "$restore_script" ]]; then
    bash "$restore_script"
  else
    echo "    restore-packages.sh no encontrado; verifique packages/ manualmente." >&2
  fi
}

detect_build_tool() {
  BUILD_TOOL=()
  BUILD_TOOL_NAME=""
  BUILD_XBUILD_FALLBACK=false

  if command -v msbuild >/dev/null 2>&1; then
    BUILD_TOOL=(msbuild)
    BUILD_TOOL_NAME="msbuild"
    return 0
  fi

  local msbuild_dll
  for msbuild_dll in \
    /usr/lib/mono/msbuild/Current/bin/MSBuild.dll \
    /usr/lib/mono/msbuild/15.0/bin/MSBuild.dll \
    /usr/lib/mono/msbuild/14.0/bin/MSBuild.dll; do
    if [[ -f "$msbuild_dll" ]]; then
      BUILD_TOOL=(mono "$msbuild_dll")
      BUILD_TOOL_NAME="msbuild (mono)"
      return 0
    fi
  done

  if command -v xbuild >/dev/null 2>&1; then
    BUILD_TOOL=(xbuild)
    BUILD_TOOL_NAME="xbuild"
    BUILD_XBUILD_FALLBACK=true
    return 0
  fi

  echo "No se encontró msbuild ni xbuild. Instale Mono:" >&2
  echo "  sudo apt install mono-complete   # repo oficial Mono (recomendado, incluye msbuild)" >&2
  echo "  https://www.mono-project.com/download/stable/" >&2
  return 1
}

show_xbuild_hint_once() {
  [[ "$BUILD_XBUILD_FALLBACK" == true && "$BUILD_HINT_SHOWN" == false ]] || return 0
  BUILD_HINT_SHOWN=true
  echo "    Nota: xbuild está obsoleto. Para msbuild: repo oficial Mono + mono-complete." >&2
}

run_build() {
  detect_build_tool || return 1
  show_xbuild_hint_once
  local -a args=("$@")
  local exit_code=0

  if [[ "$BUILD_XBUILD_FALLBACK" == true ]]; then
    # Filtra solo el banner de deprecación; conserva errores reales.
    "${BUILD_TOOL[@]}" "${args[@]}" 2>&1 | grep -v 'xbuild tool is deprecated'
    exit_code="${PIPESTATUS[0]}"
  else
    "${BUILD_TOOL[@]}" "${args[@]}"
    exit_code=$?
  fi
  return "$exit_code"
}

compile_release() {
  local official="${1:-false}"
  restore_packages
  detect_build_tool || return 1

  local -a build_args=(
    "$PROJECT"
    /p:Configuration=Release
    /p:Platform=AnyCPU
    /t:Rebuild
    /verbosity:minimal
  )

  if [[ "$official" == "true" ]] && snk_available; then
    echo "==> Compilando Release con $BUILD_TOOL_NAME (strong-name / OfficialBuild)"
    build_args+=(/p:OfficialBuild=true)
  else
    if [[ "$official" == "true" ]]; then
      echo "    EMZApps.snk no encontrado; compilando sin strong-name." >&2
    fi
    echo "==> Compilando Release con $BUILD_TOOL_NAME"
  fi

  run_build "${build_args[@]}"
}

copy_dist_assets() {
  local version="$1"
  local dist="$ROOT/dist/$version"
  local release_bin="$ROOT/NETFastSearchLibrary/bin/Release"
  rm -rf "$dist"
  mkdir -p "$dist"
  cp "$release_bin/NETFastSearchLibrary.dll" "$dist/"
  cp "$release_bin/NETFastSearchLibrary.XML" "$dist/" 2>/dev/null || true
  cp "$ROOT/LICENSE" "$dist/"
  cp "$ROOT/README.md" "$dist/"
  echo "$dist"
}

build_dist() {
  local version="$1"
  local official="${2:-false}"
  validate_version "$version" || return 1
  compile_release "$official" || return 1
  local dist
  dist="$(copy_dist_assets "$version")"
  echo "==> Listo: $dist"
  ls -la "$dist"
}

pack_nuget() {
  local version="$1"
  validate_version "$version" || return 1
  local dist="$ROOT/dist/$version"
  local release_bin="$ROOT/NETFastSearchLibrary/bin/Release"
  [[ -f "$release_bin/NETFastSearchLibrary.dll" ]] || {
    echo "Compile primero (opción 2 o release completo)." >&2
    return 1
  }
  command -v nuget >/dev/null || { echo "nuget no encontrado." >&2; return 1; }
  mkdir -p "$dist"
  local commit
  commit="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo local)"
  echo "==> Empaquetando NuGet"
  (
    cd "$ROOT/NETFastSearchLibrary"
    nuget pack NETFastSearchLibrary.Legacy.nuspec -Version "$version" -OutputDirectory "$dist" \
      -Properties "Configuration=Release;commit=$commit"
  )
  local nupkg
  nupkg="$(find "$dist" -maxdepth 1 -name '*.nupkg' -print -quit)"
  [[ -n "$nupkg" ]] || { echo "No se generó .nupkg." >&2; return 1; }
  ls -la "$nupkg"
}

push_nuget() {
  local version="$1"
  load_env
  local dist="$ROOT/dist/$version"
  local nupkg
  nupkg="$(find "$dist" -maxdepth 1 -name '*.nupkg' -print -quit 2>/dev/null || true)"
  [[ -n "$nupkg" ]] || { echo "No hay .nupkg en $dist — empaquete primero." >&2; return 1; }
  [[ -n "${NUGET_API_KEY:-}" ]] || {
    echo "Defina NUGET_API_KEY en $ENV_FILE o en el entorno." >&2
    return 1
  }

  echo "==> Publicando en nuget.org"
  # dotnet CLI usa OpenSSL del sistema; nuget.exe (Mono) falla con CERTIFICATE_VERIFY_FAILED en Linux.
  if command -v dotnet >/dev/null 2>&1; then
    dotnet nuget push "$nupkg" \
      --source https://api.nuget.org/v3/index.json \
      --api-key "$NUGET_API_KEY" \
      --skip-duplicate
    return $?
  fi

  command -v nuget >/dev/null || { echo "Se requiere dotnet CLI o nuget.exe." >&2; return 1; }
  nuget push "$nupkg" -Source https://api.nuget.org/v3/index.json \
    -ApiKey "$NUGET_API_KEY" -SkipDuplicate
}

create_git_tag() {
  local version="$1"
  local tag="v$version"
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "No es un repositorio git." >&2; return 1; }
  if git -C "$ROOT" rev-parse "$tag" >/dev/null 2>&1; then
    echo "El tag $tag ya existe." >&2
    return 1
  fi
  echo "==> Creando tag $tag"
  git -C "$ROOT" tag -a "$tag" -m "Release $tag"
}

push_git_tag() {
  local version="$1"
  local tag="v$version"
  echo "==> Empujando tag $tag a origin"
  git -C "$ROOT" push origin "$tag"
  echo "    Si release.yml está activo, CI publicará en NuGet y creará GitHub Release."
}

github_release() {
  local version="$1"
  local tag="v$version"
  local dist="$ROOT/dist/$version"
  command -v gh >/dev/null || { echo "gh CLI no encontrado (https://cli.github.com)." >&2; return 1; }
  git -C "$ROOT" rev-parse "$tag" >/dev/null 2>&1 || create_git_tag "$version" || return 1
  echo "==> Creando GitHub Release $tag"
  local assets=()
  [[ -f "$dist/NETFastSearchLibrary.dll" ]] && assets+=("$dist/NETFastSearchLibrary.dll")
  [[ -f "$dist/NETFastSearchLibrary.XML" ]] && assets+=("$dist/NETFastSearchLibrary.XML")
  local nupkg
  nupkg="$(find "$dist" -maxdepth 1 -name '*.nupkg' -print -quit 2>/dev/null || true)"
  [[ -n "$nupkg" ]] && assets+=("$nupkg")
  gh release create "$tag" --repo "$GITHUB_REPO" --title "$tag" --generate-notes "${assets[@]}"
}

do_full_release() {
  local version="$1"
  local push_tag="${2:-ask}"

  load_env
  validate_version "$version" || return 1

  echo ""
  echo "=== Release completo v$version ==="
  check_git_clean || confirm "¿Continuar de todos modos?" || return 1

  local official="false"
  if snk_available; then
    official="true"
    echo "    Strong-name: sí (EMZApps.snk)"
  else
    echo "    Strong-name: no (falta EMZApps.snk)"
  fi

  compile_release "$official" || return 1
  copy_dist_assets "$version" >/dev/null
  pack_nuget "$version" || return 1

  if [[ -n "${NUGET_API_KEY:-}" ]]; then
    push_nuget "$version" || return 1
  else
    echo "    NuGet push omitido (sin NUGET_API_KEY en release.env)." >&2
  fi

  if command -v gh >/dev/null; then
    github_release "$version" || echo "    GitHub Release falló o ya existe." >&2
  else
    echo "    GitHub Release omitido (sin gh CLI)." >&2
    create_git_tag "$version" 2>/dev/null || true
  fi

  local tag="v$version"
  case "$push_tag" in
    yes) push_git_tag "$version" ;;
    ask)
      if confirm "¿Empujar tag $tag a origin (dispara CI)?"; then
        push_git_tag "$version"
      fi
      ;;
  esac

  echo ""
  echo "==> Release v$version finalizado."
  echo "    Dist: $ROOT/dist/$version"
}

prompt_version() {
  local default
  default="$(get_assembly_version)"
  local version
  read -r -p "Versión [$default]: " version
  echo "${version:-$default}"
}

show_help() {
  cat <<EOF
Uso: $SCRIPT_NAME [comando] [argumentos]

Sin argumentos: menú interactivo.

Comandos CLI
  <version>                   Compilar dist/<version>/ (unsigned)
  --release <version>         Release completo (compilar + pack + NuGet + tag + GH)
  --build <version>           Solo compilar dist/
  --pack <version>            Empaquetar .nupkg (requiere DLL compilado)
  --push-nuget <version>      Publicar .nupkg en nuget.org
  --tag <version>             Crear tag git v<version>
  --push-tag <version>        git push origin v<version> (dispara CI)
  --github-release <version>  GitHub Release con assets de dist/
  --export-snk-base64 [ruta]  EMZApps.snk → *_base64 (secreto EMZAPPS_SNK)
  --export-pfx-base64 <pfx>   .pfx → *_base64 (secreto NUGET_SIGN_CERT_PFX)
  --restore-packages          Descargar BCL a packages/ vía curl (Linux)
  --menu                      Menú interactivo
  -h, --help                  Esta ayuda

Configuración local: $ENV_FILE (ver release.env.example)
Strong-name: $DEFAULT_SNK
Repo GitHub: $GITHUB_REPO

Notas
  - Compilación: msbuild (preferido) o xbuild. En Ubuntu instale mono-complete del repo oficial Mono.
  - En Linux: nuget pack/push con nuget.exe (Mono) falla SSL; pack usa rutas del nuspec, push usa dotnet nuget push.
  - nuget sign (Author Signing) requiere Windows; aquí se publica unsigned (Repository Signing).
  - Si empuja el tag, CI puede duplicar NuGet/GitHub Release — use una vía u otra.

EOF
}

show_menu() {
  load_env
  local version
  version="$(get_assembly_version)"
  [[ -n "$version" ]] || version="?.?.?"

  while true; do
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  NETFastSearchLibrary Legacy — Release                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo "  Versión en AssemblyInfo: $version"
    echo "  release.env: $([[ -f $ENV_FILE ]] && echo sí || echo no)"
    echo "  EMZApps.snk: $(snk_available && echo sí || echo no)"
    echo "  NUGET_API_KEY: $([[ -n ${NUGET_API_KEY:-} ]] && echo configurada || echo no)"
    echo ""
    echo "  ── Publicación ──"
    echo "  1) Release completo (compilar + NuGet + tag + GitHub Release)"
    echo "  2) Release vía CI (solo tag + push → GitHub Actions publica)"
    echo ""
    echo "  ── Pasos individuales ──"
    echo "  3) Compilar dist/ (local)"
    echo "  4) Empaquetar NuGet (.nupkg)"
    echo "  5) Publicar en nuget.org"
    echo "  6) Crear tag git (v$version)"
    echo "  7) GitHub Release (assets en dist/)"
    echo "  8) Empujar tag a origin (dispara CI)"
    echo ""
    echo "  ── Secretos / utilidades ──"
    echo "  9) Exportar EMZApps.snk → base64"
    echo " 10) Exportar .pfx → base64"
    echo " 11) Ayuda"
    echo " 12) Restaurar paquetes NuGet (curl → packages/)"
    echo "  0) Salir"
    echo ""
    read -r -p "Opción: " choice

    local picked_version="$version"
    if [[ "$choice" =~ ^[1-8]$ ]]; then
      picked_version="$(prompt_version)"
      validate_version "$picked_version" || continue
      version="$(get_assembly_version)"
    fi

    case "$choice" in
      1)
        do_full_release "$picked_version" ask || echo "Release falló." >&2
        ;;
      2)
        check_git_clean || confirm "¿Continuar?" || continue
        create_git_tag "$picked_version" && push_git_tag "$picked_version"
        ;;
      3)
        build_dist "$picked_version" "$(snk_available && echo true || echo false)"
        ;;
      4)
        pack_nuget "$picked_version"
        ;;
      5)
        push_nuget "$picked_version"
        ;;
      6)
        create_git_tag "$picked_version"
        ;;
      7)
        github_release "$picked_version"
        ;;
      8)
        push_git_tag "$picked_version"
        ;;
      9)
        export_base64 "${EMZAPPS_SNK_PATH:-$DEFAULT_SNK}" "EMZAPPS_SNK"
        ;;
      10)
        read -r -p "Ruta al .pfx: " pfx_path
        [[ -n "$pfx_path" ]] && export_base64 "$pfx_path" "NUGET_SIGN_CERT_PFX"
        ;;
      11)
        show_help
        ;;
      12)
        bash "$SCRIPT_DIR/restore-packages.sh" --force
        ;;
      0|q|Q)
        echo "Chau."
        exit 0
        ;;
      *)
        echo "Opción inválida." >&2
        ;;
    esac
  done
}

# --- Entrada ---
load_env

case "${1:-}" in
  ''|--menu)
    show_menu
    ;;
  -h|--help|help)
    show_help
    ;;
  --export-snk-base64)
    export_base64 "${2:-$DEFAULT_SNK}" "EMZAPPS_SNK"
    ;;
  --export-pfx-base64)
    [[ -n "${2:-}" ]] || { echo "Indique ruta al .pfx" >&2; exit 1; }
    export_base64 "$2" "NUGET_SIGN_CERT_PFX"
    ;;
  --export-snk-base64=*)
    export_base64 "${1#*=}" "EMZAPPS_SNK"
    ;;
  --export-pfx-base64=*)
    export_base64 "${1#*=}" "NUGET_SIGN_CERT_PFX"
    ;;
  --release)
    [[ -n "${2:-}" ]] || { echo "Uso: $SCRIPT_NAME --release <version>" >&2; exit 1; }
    do_full_release "$2" ask
    ;;
  --build)
    [[ -n "${2:-}" ]] || { echo "Uso: $SCRIPT_NAME --build <version>" >&2; exit 1; }
    build_dist "$2" "$(snk_available && echo true || echo false)"
    ;;
  --pack)
    [[ -n "${2:-}" ]] || { echo "Uso: $SCRIPT_NAME --pack <version>" >&2; exit 1; }
    pack_nuget "$2"
    ;;
  --push-nuget)
    [[ -n "${2:-}" ]] || { echo "Uso: $SCRIPT_NAME --push-nuget <version>" >&2; exit 1; }
    push_nuget "$2"
    ;;
  --tag)
    [[ -n "${2:-}" ]] || { echo "Uso: $SCRIPT_NAME --tag <version>" >&2; exit 1; }
    create_git_tag "$2"
    ;;
  --push-tag)
    [[ -n "${2:-}" ]] || { echo "Uso: $SCRIPT_NAME --push-tag <version>" >&2; exit 1; }
    push_git_tag "$2"
    ;;
  --github-release)
    [[ -n "${2:-}" ]] || { echo "Uso: $SCRIPT_NAME --github-release <version>" >&2; exit 1; }
    github_release "$2"
    ;;
  --restore-packages)
    bash "$SCRIPT_DIR/restore-packages.sh" "${2:---force}"
    ;;
  -*)
    echo "Opción desconocida: $1" >&2
    echo "Use: $SCRIPT_NAME --help" >&2
    exit 1
    ;;
  *)
    build_dist "$1" "$(snk_available && echo true || echo false)"
    ;;
esac
