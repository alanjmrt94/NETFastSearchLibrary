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
EMZAPPS_SNK_PATH="${EMZAPPS_SNK_PATH:-$DEFAULT_SNK}"
PROJECT="$ROOT/NETFastSearchLibrary/NETFastSearchLibrary.csproj"
ASSEMBLY_INFO="$ROOT/NETFastSearchLibrary/Properties/AssemblyInfo.cs"
GITHUB_REPO="${GITHUB_REPO:-alanjmrt94/NETFastSearchLibrary}"

# --- Utilidades ---

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
  [[ -f "$EMZAPPS_SNK_PATH" ]]
}

export_base64() {
  local src="$1"
  local secret_name="$2"
  [[ -f "$src" ]] || { echo "No se encontró: $src" >&2; return 1; }
  local out="${src}_base64"
  base64 -w0 "$src" > "$out"
  echo "==> Exportado: $out"
  echo "    Secreto GitHub: $secret_name"
  echo "    Copie el contenido (una sola línea) en Environment → nuget-publish → Secrets."
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

tag_exists_remote() {
  local tag="$1"
  git -C "$ROOT" ls-remote --tags origin "refs/tags/${tag}" 2>/dev/null | grep -q .
}

create_git_tag() {
  local version="$1"
  local tag="v$version"
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "No es un repositorio git." >&2; return 1; }
  if git -C "$ROOT" rev-parse "$tag" >/dev/null 2>&1; then
    echo "    Tag local $tag ya existe." >&2
    return 0
  fi
  if tag_exists_remote "$tag"; then
    echo "    Tag remoto $tag ya existe en origin." >&2
    return 0
  fi
  echo "==> Creando tag $tag"
  git -C "$ROOT" tag -a "$tag" -m "Release $tag"
}

push_git_tag() {
  local version="$1"
  local tag="v$version"
  if tag_exists_remote "$tag"; then
    echo "    Tag $tag ya está en origin; omitiendo push." >&2
    echo "    Release: https://github.com/${GITHUB_REPO}/releases/tag/${tag}"
    return 0
  fi
  git -C "$ROOT" rev-parse "$tag" >/dev/null 2>&1 || create_git_tag "$version" || return 1
  echo "==> Empujando tag $tag a origin"
  if git -C "$ROOT" push origin "$tag"; then
    echo "    CI (release.yml) publicará en NuGet vía Trusted Publishing."
    echo "    Ver: gh run list --workflow=release.yml"
  else
    echo "    Push del tag falló (puede existir ya en remoto)." >&2
    return 1
  fi
}

github_release() {
  local version="$1"
  local tag="v$version"
  local dist="$ROOT/dist/$version"
  command -v gh >/dev/null || { echo "gh CLI no encontrado (https://cli.github.com)." >&2; return 1; }

  if gh release view "$tag" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "    GitHub Release $tag ya existe." >&2
    echo "    https://github.com/${GITHUB_REPO}/releases/tag/${tag}"
    local nupkg asset
    nupkg="$(find "$dist" -maxdepth 1 -name '*.nupkg' -print -quit 2>/dev/null || true)"
    for asset in "$nupkg" "$dist/NETFastSearchLibrary.dll" "$dist/NETFastSearchLibrary.XML"; do
      [[ -f "$asset" ]] || continue
      gh release upload "$tag" "$asset" --repo "$GITHUB_REPO" --clobber 2>/dev/null || true
    done
    return 0
  fi

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

  validate_version "$version" || return 1

  echo ""
  echo "=== Release v$version (local + CI) ==="
  echo "  Pipeline: compilar → pack → GitHub Release → push tag → NuGet (Trusted Publishing)"
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
      if confirm "¿Empujar tag $tag a origin (CI publica en NuGet)?"; then
        push_git_tag "$version"
      else
        echo "    Sin tag: NuGet.org no se publicará (Trusted Publishing requiere push del tag)." >&2
      fi
      ;;
  esac

  echo ""
  echo "==> Release v$version finalizado."
  echo "    Dist: $ROOT/dist/$version"
  echo "    NuGet: gh run list --workflow=release.yml"
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
  --release <version>         Release: compilar + pack + GH Release + tag (NuGet vía CI)
  --build <version>           Solo compilar dist/
  --pack <version>            Empaquetar .nupkg (requiere DLL compilado)
  --tag <version>             Crear tag git v<version>
  --push-tag <version>        git push origin v<version> (dispara CI)
  --github-release <version>  GitHub Release con assets de dist/
  --export-snk-base64 [ruta]  EMZApps.snk → *_base64 (secreto EMZAPPS_SNK)
  --export-pfx-base64 <pfx>   .pfx → *_base64 (secreto NUGET_SIGN_CERT_PFX)
  --restore-packages          Descargar BCL a packages/ vía curl (Linux)
  --menu                      Menú interactivo
  -h, --help                  Esta ayuda

Strong-name: $DEFAULT_SNK (override: EMZAPPS_SNK_PATH)
Repo GitHub: $GITHUB_REPO

Notas
  - Compilación: msbuild (preferido) o xbuild. En Ubuntu instale mono-complete del repo oficial Mono.
  - NuGet.org: Trusted Publishing en release.yml (environment nuget-publish). Ver docs/CI.md.
  - nuget sign (Author Signing) requiere Windows; aquí se publica unsigned (Repository Signing).
  - Empujar el tag dispara CI; evite publicar NuGet manualmente si CI está activo.

EOF
}

show_menu() {
  local version
  version="$(get_assembly_version)"
  [[ -n "$version" ]] || version="?.?.?"

  while true; do
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  NETFastSearchLibrary Legacy — Release                   ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo "  Versión en AssemblyInfo: $version"
    echo "  EMZApps.snk: $(snk_available && echo sí || echo no)"
    echo "  NuGet.org: Trusted Publishing (CI, environment nuget-publish)"
    echo ""
    echo "  ── Publicación ──"
    echo "  1) Release (compilar + pack + GH Release + tag → CI publica NuGet)"
    echo "  2) Solo tag + push (dispara CI sin build local)"
    echo ""
    echo "  ── Pasos individuales ──"
    echo "  3) Compilar dist/ (local)"
    echo "  4) Empaquetar NuGet (.nupkg)"
    echo "  5) Crear tag git (v$version)"
    echo "  6) GitHub Release (assets en dist/)"
    echo "  7) Empujar tag a origin (dispara CI)"
    echo ""
    echo "  ── Secretos / utilidades ──"
    echo "  8) Exportar EMZApps.snk → base64"
    echo "  9) Exportar .pfx → base64"
    echo " 10) Ayuda"
    echo " 11) Restaurar paquetes NuGet (curl → packages/)"
    echo "  0) Salir"
    echo ""
    read -r -p "Opción: " choice

    local picked_version="$version"
    if [[ "$choice" =~ ^[1-7]$ ]]; then
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
        create_git_tag "$picked_version"
        ;;
      6)
        github_release "$picked_version"
        ;;
      7)
        push_git_tag "$picked_version"
        ;;
      8)
        export_base64 "$EMZAPPS_SNK_PATH" "EMZAPPS_SNK"
        ;;
      9)
        read -r -p "Ruta al .pfx: " pfx_path
        [[ -n "$pfx_path" ]] && export_base64 "$pfx_path" "NUGET_SIGN_CERT_PFX"
        ;;
      10)
        show_help
        ;;
      11)
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
