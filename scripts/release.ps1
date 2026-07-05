#Requires -Version 5.1
<#
.SYNOPSIS
    Compila, firma, empaqueta y publica NETFastSearchLibrary.Legacy.

.DESCRIPTION
    Flujo local + CI (Trusted Publishing):
      1. Restore NuGet + MSBuild Release (strong-name)
      2. Salida en dist/<version>/
      3. nuget pack + Author Signing opcional (Authenticode)
      4. Tag git + GitHub Release (opcional, requiere gh CLI)
      5. NuGet.org lo publica release.yml al recibir el tag (OIDC)

    Requiere Windows, MSBuild, NuGet CLI 6.x+.

.PARAMETER Version
    Versión semver (ej. 1.0.5). Debe coincidir con AssemblyInfo.cs.

.PARAMETER DistOnly
    Solo compila y genera dist/ (sin pack, tag ni GitHub Release).

.PARAMETER SkipGitHubRelease
    No crea release en GitHub.

.PARAMETER SkipGitTag
    No crea ni empuja el tag git.

.PARAMETER Force
    Continúa aunque el árbol git no esté limpio.

.EXAMPLE
    .\scripts\release.ps1 -Version 1.0.5

.EXAMPLE
    .\scripts\release.ps1 -Version 1.0.5 -DistOnly

.PARAMETER ExportSnkBase64
    Exporta el .snk a base64 (una línea) en <archivo>_base64 y termina.

.PARAMETER ExportPfxBase64
    Exporta el .pfx a base64 (una línea) en <archivo>_base64 y termina.
    Requiere -SignCertPath.

.EXAMPLE
    .\scripts\release.ps1 -ExportSnkBase64

.EXAMPLE
    .\scripts\release.ps1 -ExportPfxBase64 -SignCertPath C:\ruta\codigo-firma.pfx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[\w\.]+)?$')]
    [string] $Version,

    [switch] $ExportSnkBase64,
    [switch] $ExportPfxBase64,
    [switch] $DistOnly,
    [switch] $SkipGitHubRelease,
    [switch] $SkipGitTag,
    [switch] $Force,

    [string] $SnkPath,
    [string] $SignCertPath,
    [string] $SignCertPassword,
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Resolve-Tool([string] $Name, [string[]] $Candidates) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    throw "No se encontró '$Name'. Instálelo o agréguelo al PATH."
}

function Get-AssemblyInfoVersion([string] $AssemblyInfoPath) {
    $content = Get-Content -LiteralPath $AssemblyInfoPath -Raw
    if ($content -match 'AssemblyVersion\("(?<ver>\d+\.\d+\.\d+)') {
        return $Matches['ver']
    }
    throw "No se pudo leer AssemblyVersion en $AssemblyInfoPath"
}

function Invoke-External {
    param(
        [string] $FilePath,
        [string[]] $ArgumentList
    )
    Write-Host "    $FilePath $($ArgumentList -join ' ')" -ForegroundColor DarkGray
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Falló: $FilePath (código $LASTEXITCODE)"
    }
}

function Export-FileBase64([string] $FilePath, [string] $SecretName) {
    $resolved = (Resolve-Path -LiteralPath $FilePath).Path
    $outPath = "${resolved}_base64"
    $bytes = [IO.File]::ReadAllBytes($resolved)
    $encoded = [Convert]::ToBase64String($bytes)
    [IO.File]::WriteAllText($outPath, $encoded, [Text.UTF8Encoding]::new($false))
    Write-Host "    Origen:  $resolved" -ForegroundColor Green
    Write-Host "    Salida:  $outPath" -ForegroundColor Green
    Write-Host "    Secreto GitHub (environment nuget-publish): $SecretName" -ForegroundColor Yellow
    return $outPath
}

function Show-ReleaseHelp {
    @"

Uso: .\scripts\release.ps1 [opciones]

Release
  -Version <semver>           Build firmado + dist + tag + GitHub (NuGet vía CI)
  -DistOnly                   Solo compila dist/ (sin pack, tag ni GitHub)

Exportación base64 (*_base64, gitignored)
  -ExportSnkBase64            → EMZAPPS_SNK
  -ExportPfxBase64            → NUGET_SIGN_CERT_PFX (requiere -SignCertPath)

Secretos GitHub (environment: nuget-publish)
  NUGET_USER                  username nuget.org (Trusted Publishing)
  EMZAPPS_SNK                 .snk en base64
  NUGET_SIGN_CERT_PFX         .pfx en base64 (opcional)
  NUGET_SIGN_CERT_PASSWORD    contraseña del .pfx (opcional)

Ver docs/CI.md. Linux: ./scripts/build-dist.sh --help

"@ | Write-Host
}

# --- Configuración ---
$projectDir = Join-Path $RepoRoot 'NETFastSearchLibrary'
$SnkPath = if ($SnkPath) { $SnkPath } else { Join-Path $projectDir 'EMZApps.snk' }

if ($ExportSnkBase64 -and $ExportPfxBase64) {
    throw 'Use solo uno: -ExportSnkBase64 o -ExportPfxBase64.'
}

if ($ExportSnkBase64) {
    Write-Step 'Exportando strong-name a base64'
    if (-not (Test-Path -LiteralPath $SnkPath)) {
        throw "No se encontró la clave strong-name: $SnkPath"
    }
    Export-FileBase64 -FilePath $SnkPath -SecretName 'EMZAPPS_SNK' | Out-Null
    exit 0
}

if ($ExportPfxBase64) {
    Write-Step 'Exportando certificado PFX a base64'
    if ([string]::IsNullOrWhiteSpace($SignCertPath) -or -not (Test-Path -LiteralPath $SignCertPath)) {
        throw 'Indique -SignCertPath con la ruta al .pfx.'
    }
    Export-FileBase64 -FilePath $SignCertPath -SecretName 'NUGET_SIGN_CERT_PFX' | Out-Null
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    Show-ReleaseHelp
    throw 'Indique -Version o use -ExportSnkBase64 / -ExportPfxBase64.'
}

$csproj = Join-Path $projectDir 'NETFastSearchLibrary.csproj'
$nuspec = Join-Path $projectDir 'NETFastSearchLibrary.Legacy.nuspec'
$solution = Join-Path $RepoRoot 'NETFastSearchLibrary.sln'
$assemblyInfo = Join-Path $projectDir 'Properties\AssemblyInfo.cs'

$tag = "v$Version"
$distDir = Join-Path $RepoRoot "dist\$Version"
$commit = (git -C $RepoRoot rev-parse HEAD 2>$null)
if (-not $commit) { $commit = 'local' }

Write-Step "Validando entorno"
if (-not $Force) {
    $status = git -C $RepoRoot status --porcelain 2>$null
    if ($status) {
        throw "El árbol git tiene cambios sin commit. Use -Force para ignorar.`n$status"
    }
}

$assemblyVersion = Get-AssemblyInfoVersion -AssemblyInfoPath $assemblyInfo
if ($assemblyVersion -ne $Version) {
    throw "La versión del script ($Version) no coincide con AssemblyInfo.cs ($assemblyVersion)."
}

$nuget = Resolve-Tool 'nuget' @(
    "${env:ProgramFiles(x86)}\NuGet\nuget.exe",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links\nuget.exe"
)
$msbuild = Resolve-Tool 'msbuild' @(
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
)

if (-not (Test-Path -LiteralPath $SnkPath)) {
    throw "No se encontró la clave strong-name: $SnkPath"
}

$authorSignReady = (
    -not [string]::IsNullOrWhiteSpace($SignCertPath) -and
    (Test-Path -LiteralPath $SignCertPath) -and
    -not [string]::IsNullOrWhiteSpace($SignCertPassword)
)

# --- Restore + Build ---
Write-Step "Restaurando paquetes NuGet"
Invoke-External -FilePath $nuget -ArgumentList @('restore', $solution)

Write-Step "Compilando Release (strong-name)"
Invoke-External -FilePath $msbuild -ArgumentList @(
    $csproj,
    '/p:Configuration=Release',
    '/p:Platform=AnyCPU',
    '/p:OfficialBuild=true',
    '/t:Rebuild',
    '/verbosity:minimal'
)

$releaseBin = Join-Path $projectDir 'bin\Release'
$dll = Join-Path $releaseBin 'NETFastSearchLibrary.dll'
$xml = Join-Path $releaseBin 'NETFastSearchLibrary.XML'

foreach ($artifact in @($dll, $xml)) {
    if (-not (Test-Path -LiteralPath $artifact)) {
        throw "Artefacto esperado no generado: $artifact"
    }
}

# --- dist/ ---
Write-Step "Preparando dist/$Version"
if (Test-Path -LiteralPath $distDir) {
    Remove-Item -LiteralPath $distDir -Recurse -Force
}
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

Copy-Item -LiteralPath $dll -Destination $distDir
Copy-Item -LiteralPath $xml -Destination $distDir
Copy-Item -LiteralPath (Join-Path $RepoRoot 'LICENSE') -Destination $distDir
Copy-Item -LiteralPath (Join-Path $RepoRoot 'README.md') -Destination $distDir

Write-Host "    dist: $distDir" -ForegroundColor Green

if ($DistOnly) {
    Write-Step 'DistOnly: omitiendo pack, tag y GitHub Release.'
    exit 0
}

# --- Pack ---
Write-Step 'Empaquetando NuGet'
Invoke-External -FilePath $nuget -ArgumentList @(
    'pack', $nuspec,
    '-Version', $Version,
    '-OutputDirectory', $distDir,
    '-Properties', "Configuration=Release;commit=$commit"
)

$nupkg = Get-ChildItem -Path $distDir -Filter '*.nupkg' | Select-Object -First 1
if (-not $nupkg) {
    throw 'No se generó ningún .nupkg.'
}

# --- Sign nupkg (Author Signing opcional) ---
if ($authorSignReady) {
    Write-Step 'Firmando paquete NuGet (Author / Authenticode)'
    Invoke-External -FilePath $nuget -ArgumentList @(
        'sign', $nupkg.FullName,
        '-CertificatePath', (Resolve-Path -LiteralPath $SignCertPath).Path,
        '-CertificatePassword', $SignCertPassword,
        '-Timestamper', 'http://timestamp.digicert.com',
        '-TimestampHashAlgorithm', 'SHA256',
        '-HashAlgorithm', 'SHA256',
        '-NonInteractive'
    )
    Write-Step 'Verificando firma del paquete'
    Invoke-External -FilePath $nuget -ArgumentList @('verify', '-Signatures', $nupkg.FullName)
} else {
    Write-Host '    Author Signing omitido (sin certificado). nuget.org aplicará Repository Signing.' -ForegroundColor Yellow
}

Write-Host '    NuGet.org: release.yml (Trusted Publishing) al empujar el tag.' -ForegroundColor Yellow

# --- Git tag ---
if (-not $SkipGitTag) {
    Write-Step "Creando tag $tag"
    $existingTag = git -C $RepoRoot tag -l $tag
    if ($existingTag) {
        if (-not $Force) {
            throw "El tag $tag ya existe. Use -Force para continuar."
        }
        Write-Host "    Tag $tag ya existía (Force)." -ForegroundColor Yellow
    } else {
        Invoke-External -FilePath 'git' -ArgumentList @('-C', $RepoRoot, 'tag', '-a', $tag, '-m', "Release $tag")
    }
    Invoke-External -FilePath 'git' -ArgumentList @('-C', $RepoRoot, 'push', 'origin', $tag)
} else {
    Write-Host '    SkipGitTag: no se creó tag.' -ForegroundColor Yellow
}

# --- GitHub Release ---
if (-not $SkipGitHubRelease) {
    $gh = Get-Command 'gh' -ErrorAction SilentlyContinue
    if (-not $gh) {
        throw 'gh CLI no encontrado. Instálelo o use -SkipGitHubRelease.'
    }
    Write-Step "Creando GitHub Release $tag"
    $releaseAssets = @(
        $nupkg.FullName,
        (Join-Path $distDir 'NETFastSearchLibrary.dll'),
        (Join-Path $distDir 'NETFastSearchLibrary.XML')
    )
    $ghArgs = @(
        'release', 'create', $tag,
        '--title', $tag,
        '--generate-notes',
        '--repo', 'alanjmrt94/NETFastSearchLibrary'
    ) + $releaseAssets
    Invoke-External -FilePath $gh.Source -ArgumentList $ghArgs
} else {
    Write-Host '    SkipGitHubRelease: no se creó release en GitHub.' -ForegroundColor Yellow
}

if (-not $SkipGitTag) {
    Write-Host "`n    CI: release.yml publicará en NuGet vía Trusted Publishing." -ForegroundColor Yellow
    Write-Host '    Ver: gh run list --workflow=release.yml' -ForegroundColor Yellow
}

Write-Step 'Release completado'
Write-Host "    Versión:  $Version"
Write-Host "    Dist:     $distDir"
Write-Host "    NuGet:    $($nupkg.Name)"
Write-Host "    Tag:      $tag"
