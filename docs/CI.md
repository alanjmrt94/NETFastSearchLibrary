# Integración continua (GitHub Actions)

El repositorio usa [GitHub Actions](https://docs.github.com/en/actions) para build y publicación en NuGet.

## Workflows

| Archivo | Disparador | Qué hace |
|---------|------------|----------|
| `.github/workflows/ci.yml` | Push / PR a `master` o `main` | `restore` → instala reference assemblies net40 → `build` Release (unsigned) |
| `.github/workflows/release.yml` | Push de tag `v*.*.*` | strong-name → pack → firma opcional → [NuGet.org](https://www.nuget.org/) vía Trusted Publishing → GitHub Release |

## Node.js 24 en los runners

GitHub deprecó Node.js 20 en los runners. Ambos workflows declaran:

```yaml
env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
```

| Acción | Versión | Runtime |
|--------|---------|---------|
| `actions/checkout` | `@v5` | Node 24 |
| `actions/setup-dotnet` | `@v5` | Node 24 |
| `nuget/setup-nuget` | `@v4` | Node 24 |
| `NuGet/login` | `@v1` | Node 24 |

## Badge de estado

```markdown
![CI](https://github.com/alanjmrt94/NETFastSearchLibrary/actions/workflows/ci.yml/badge.svg?branch=master)
```

## Publicar una versión en NuGet

1. Actualizar versión en `NETFastSearchLibrary/Properties/AssemblyInfo.cs` y `app.manifest`.
2. Actualizar `CHANGELOG.md` con la entrada de la versión.

### GitHub Actions → NuGet.org (Trusted Publishing)

El workflow `release.yml` usa [Trusted Publishing](https://learn.microsoft.com/en-us/nuget/nuget-org/trusted-publishing) (OIDC). **No se usan API keys permanentes.**

#### 1. Environment en GitHub

Los secrets de publicación van en un **Environment**, no a nivel de repositorio.

**GitHub** → repo → **Settings** → **Environments** → **New environment**

| Campo | Valor |
|-------|--------|
| Name | `nuget-publish` |

Dentro del environment → **Environment secrets**:

| Secret | ¿Obligatorio? | Descripción |
|--------|---------------|-------------|
| `NUGET_USER` | **Sí** | Username **nuget.org de quien creó la política** de Trusted Publishing |
| `EMZAPPS_SNK` | **Sí** | Strong-name `EMZApps.snk` en **base64** |
| `NUGET_SIGN_CERT_PFX` | No | Certificado Authenticode `.pfx` en **base64** |
| `NUGET_SIGN_CERT_PASSWORD` | No | Contraseña del `.pfx` (requerida si hay certificado) |

Sin `NUGET_SIGN_CERT_*`: el `.nupkg` se publica **sin Author Signing**; nuget.org aplica **Repository Signing**.

Exportar strong-name a base64:

```bash
./scripts/build-dist.sh --export-snk-base64
```

**Opcional — reglas de protección** (misma pantalla del environment):

- **Deployment branches:** *Selected branches and tags* → patrón `v*`.
- **Required reviewers:** activar si querés aprobación manual antes de publicar.

El job en `release.yml` declara `environment: nuget-publish`; solo ese job accede a esos secrets.

#### 2. Política en nuget.org

**nuget.org** → cuenta → **Trusted Publishing** → crear o editar política.

Los valores deben coincidir **exactamente** con el repo y el workflow:

| Campo en nuget.org | Valor |
|--------------------|--------|
| Package owner | `alanjmrt94` |
| Repository Owner (GitHub) | `alanjmrt94` |
| Repository | `NETFastSearchLibrary` |
| Workflow File | `release.yml` |
| Environment | `nuget-publish` |

Errores frecuentes:

- **Repository Owner** distinto al owner real del repo en GitHub.
- **Environment** distinto al declarado en `release.yml` (p. ej. `release` vs `nuget-publish`).

#### 3. Tag y push

```bash
git tag -a v1.0.5 -m "Release v1.0.5"
git push origin v1.0.5
```

O usar los scripts locales (ver abajo), que crean el tag y disparan el workflow.

El workflow compila con strong-name, empaqueta, firma opcionalmente (`nuget sign`), obtiene una credencial efímera vía `NuGet/login@v1` y sube `NETFastSearchLibrary.Legacy.<version>.nupkg`. `--skip-duplicate` evita fallar si el paquete ya existe.

### Firma del paquete (solo en CI)

| Tipo | Qué firma | Secret en `nuget-publish` | Por defecto |
|------|-----------|----------------------------|-------------|
| **Strong-name** | Ensamblado `NETFastSearchLibrary.dll` | `EMZAPPS_SNK` (base64) | **Sí** (release) |
| **Author Signing** | `.nupkg` (Authenticode) | `NUGET_SIGN_CERT_PFX` + `NUGET_SIGN_CERT_PASSWORD` | Desactivado |
| **Repository Signing** | `.nupkg` en nuget.org | Automático al publicar | **Sí** |

`ci.yml` y builds locales compilan sin strong-name. Solo `release.yml` aplica firma strong-name.

> **Nota:** No activar «Require signing by a registered certificate» en nuget.org hasta registrar el certificado Authenticode.

### Scripts locales

| Script | Plataforma | NuGet.org |
|--------|------------|-----------|
| `scripts/build-dist.sh` | Linux (Mono) | **CI** vía Trusted Publishing (push del tag) |
| `scripts/release.ps1` | Windows | **CI** vía Trusted Publishing (push del tag) |

Pipeline recomendado:

| Paso | Acción |
|------|--------|
| 1 | **Local:** compilar → empaquetar → (opcional) GitHub Release con assets |
| 2 | **GitHub:** tag `v*` → push |
| 3 | **CI:** `release.yml` → `NuGet/login` (OIDC) → `dotnet nuget push` |

```bash
./scripts/build-dist.sh              # menú interactivo
./scripts/build-dist.sh --release 1.0.5
gh run list --workflow=release.yml
```

**Requisitos Linux:** Mono (`mono-complete`), `git`, `gh auth login`. NuGet.org lo publica CI.

**Requisitos Windows:**

```powershell
.\scripts\release.ps1 -Version 1.0.5
```

NuGet lo publica CI al recibir el tag (`release.yml`).

## Solución de problemas (Trusted Publishing)

### Error 401: «No matching trust policy owned by user …»

El paso `NuGet/login@v1` falla si no hay una política que coincida con el token OIDC. Revisá en este orden:

1. **`NUGET_USER`:** username de nuget.org de quien **creó** la política (p. ej. `alanjmrt94`).
2. **Repository Owner:** `alanjmrt94`.
3. **Repository:** `NETFastSearchLibrary`.
4. **Workflow file:** `release.yml`.
5. **Environment:** `nuget-publish`.

En GitHub → **Settings** → **Environments** → `nuget-publish` → verificá `NUGET_USER`.

```bash
gh run list --workflow=release.yml
gh run rerun <run-id> --failed
```

### Error MSB3644 (.NET Framework 4.0 reference assemblies)

Los runners `windows-latest` no incluyen el targeting pack de .NET 4.0. Los workflows instalan las reference assemblies vía paquete NuGet antes del build (sin importar el `.targets` en el `.csproj`, incompatible con Mono/xbuild en Linux).

### Warning «Node.js 20 is deprecated»

Actualizá las acciones JavaScript a versiones con runtime Node 24 (ver tabla arriba).

## Verificación local (equivalente al CI)

Linux:

```bash
./scripts/restore-packages.sh
./scripts/build-dist.sh 1.0.5
```

Windows:

```powershell
nuget restore NETFastSearchLibrary.sln
msbuild NETFastSearchLibrary\NETFastSearchLibrary.csproj /p:Configuration=Release /t:Rebuild
```
