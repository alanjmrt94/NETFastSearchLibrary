# NETFastSearchLibrary (Legacy)

<table>
<tr>
<td width="220" valign="top"><img src="logo_base.png" alt="NETFastSearchLibrary" width="200"/></td>
<td valign="top">

**Versión:** `1.0.4` · **Estado:** mantenimiento mínimo (solo .NET Framework 4.0)  
**Autor:** [alanjmrt94](https://github.com/alanjmrt94) · **Organización:** EMZ Apps  
**Repositorio sucesor:** [**NetcoreFSL**](https://github.com/alanjmrt94/netcore-fsl) — biblioteca multiplataforma para .NET 8

> Este repositorio conserva la biblioteca original para **.NET Framework 4.0** y **Windows XP+**.  
> Para proyectos nuevos en .NET 8 (Windows, Linux, macOS), use [NetcoreFSL](https://github.com/alanjmrt94/netcore-fsl).

Biblioteca multiproceso escrita en C# que permite encontrar archivos de forma recursiva mediante patrones o delegados personalizados, con métodos estáticos y API basada en eventos.

</td>
</tr>
</table>

## Características

- Búsqueda recursiva de **archivos** por patrón (`*.txt`) o por delegado `Func<FileInfo, bool>`
- Métodos estáticos síncronos y asíncronos (`GetFiles`, `GetFilesFast`, `GetFilesFastAsync`)
- API por instancia con eventos (`FilesFound`, `SearchCompleted`) y cancelación
- Búsqueda en **varias carpetas** con `FileSearchMultiple`
- Paralelismo mediante pool de hilos (`GetFilesFast*`, `StartSearchAsync`)
- Compatible con **Windows XP** y superior (.NET Framework 4.0)
- Las excepciones `UnauthorizedAccessException` se suprimen durante el recorrido

## Requisitos

- [.NET Framework 4.0](https://dotnet.microsoft.com/download/dotnet-framework/net40) o superior
- Windows XP o posterior
- Visual Studio 2015+ (requerido por `nameof` en validaciones; recomendado VS 2019/2022)

## Compilar desde el código fuente (Windows)

Requiere **Windows**, **Visual Studio** (o Build Tools) con soporte para **.NET Framework 4.0** y **NuGet**.

Salida: `NETFastSearchLibrary\bin\Release\NETFastSearchLibrary.dll` (+ `.XML` de documentación).

> **Nota — firma y NuGet:** Los builds locales **no están firmados**. CI firma el DLL con strong name (`PublicKeyToken` `a8ab9e59c05f5f54`). El `.nupkg` se publica **sin Author Signing**; nuget.org aplica **Repository Signing**. La confianza viene del paquete en **nuget.org** publicado por tu cuenta, no de compilar un fork.

### Build local (desarrollo / PR)

```text
nuget restore NETFastSearchLibrary.sln
msbuild NETFastSearchLibrary.sln /p:Configuration=Release /p:Platform="Any CPU"
```

### Build oficial firmado (solo CI / mantenedores)

```text
msbuild NETFastSearchLibrary.sln /p:Configuration=Release /p:Platform="Any CPU" /p:OfficialBuild=true
```

Requiere `NETFastSearchLibrary/EMZApps.snk` (clave en secreto de CI, no versionada).

## Instalación

### NuGet (recomendado)

```text
Install-Package NETFastSearchLibrary.Legacy
```

Paquete firmado por el autor (Authenticode) y publicado desde CI oficial en [nuget.org](https://www.nuget.org/packages/NETFastSearchLibrary.Legacy).

> Si el paquete aún no está publicado, use Releases o compilación manual mientras tanto.

### Manual

1. Descargue la última versión desde [Releases](https://github.com/alanjmrt94/NETFastSearchLibrary/releases) o compile la solución.
2. Copie `NETFastSearchLibrary.dll` en su proyecto.
3. Agregue la referencia: Explorador de soluciones → clic derecho en **Referencias** → **Agregar referencia** → **Examinar**.
4. Establezca la plataforma de destino en **.NET Framework 4.0** como mínimo.
5. Agregue al inicio del archivo:

```csharp
using NETFastSearchLibrary;
```

## API pública

### Clase `FileSearch`

| Miembro | Descripción |
|---------|-------------|
| `GetFiles(folder, pattern)` | Búsqueda recursiva en un hilo |
| `GetFiles(folder, isValid)` | Búsqueda con delegado en un hilo |
| `GetFilesFast(...)` | Búsqueda paralela (pool de hilos) |
| `GetFilesFastAsync(...)` | Variante asíncrona |
| `StartSearch()` / `StartSearchAsync()` | Búsqueda con eventos en tiempo real |
| `StopSearch()` | Detiene la búsqueda activa |

Constructores de instancia aceptan patrón o delegado, opcionalmente `CancellationTokenSource`, `ExecuteHandlers` y `suppressOperationCanceledException`.

### Clase `FileSearchMultiple`

Igual que `FileSearch`, pero el constructor recibe `List<string>` de carpetas raíz.

### `ExecuteHandlers`

| Valor | Comportamiento |
|-------|----------------|
| `InCurrentTask` | Los manejadores de `FilesFound` se ejecutan en la tarea que encontró los archivos |
| `InNewTask` | Los manejadores se ejecutan en una tarea nueva |

## Ejemplos de uso

### Búsqueda estática simple

```csharp
using System.Collections.Generic;
using System.IO;
using NETFastSearchLibrary;

// Un hilo — devuelve la lista al terminar
List<FileInfo> files = FileSearch.GetFiles(@"C:\Users", "*.txt");

// Varios hilos — más rápido en procesadores multinúcleo
List<FileInfo> fast = FileSearch.GetFilesFast(@"C:\Users", "*SomePattern*.txt");

// Asíncrono
Task<List<FileInfo>> task = FileSearch.GetFilesFastAsync(@"C:\", "a?.txt");
```

### Búsqueda con delegado

```csharp
using System;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using NETFastSearchLibrary;

Task<List<FileInfo>> task = FileSearch.GetFilesFastAsync(@"D:\", (f) =>
{
    return (f.Name.Contains("Pattern") || f.Name.Contains("Pattern2")) &&
           f.LastAccessTime >= new DateTime(2018, 3, 1) && f.Length > 1073741824;
});

// Con expresión regular
Task<List<FileInfo>> mp3 = FileSearch.GetFilesFastAsync(@"D:\", (f) =>
    Regex.IsMatch(f.Name, @".*Imagine[\s_-]Dragons.*\.mp3$"));
```

### Búsqueda con eventos y cancelación

```csharp
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;
using NETFastSearchLibrary;

class Searcher
{
    private static readonly object locker = new object();
    private FileSearch searcher;
    private List<FileInfo> files;

    public Searcher()
    {
        files = new List<FileInfo>();
    }

    public void StartSearch()
    {
        CancellationTokenSource tokenSource = new CancellationTokenSource();

        searcher = new FileSearch(@"C:\", (f) =>
            Regex.IsMatch(f.Name, @".*[iI]magine[\s_-][dD]ragons.*\.mp3$"),
            tokenSource);

        searcher.FilesFound += (sender, arg) =>
        {
            lock (locker)
            {
                arg.Files.ForEach(f =>
                {
                    files.Add(f);
                    Console.WriteLine("File: {0}", f.FullName);
                });

                if (files.Count >= 10)
                    searcher.StopSearch();
            }
        };

        searcher.SearchCompleted += (sender, arg) =>
        {
            Console.WriteLine(arg.IsCanceled ? "Search stopped." : "Search completed.");
            Console.WriteLine("Quantity: {0}", files.Count);
        };

        searcher.StartSearchAsync();
    }
}
```

> Los manejadores de `FilesFound` **no son thread-safe**. Use `lock` o colecciones de `System.Collections.Concurrent`.

### Búsqueda en varias carpetas

```csharp
using System.Collections.Generic;
using System.IO;
using System.Threading;
using NETFastSearchLibrary;

List<string> folders = new List<string>
{
    @"C:\Users\Public",
    @"C:\Windows\System32",
    @"D:\Program Files"
};

FileSearchMultiple multiple = new FileSearchMultiple(folders, (f) =>
    f.Extension == ".cs" && f.Name.Contains("Program"),
    new CancellationTokenSource());

multiple.FilesFound += (s, e) => { /* ... */ };
multiple.StartSearchAsync();
```

### Opciones avanzadas del constructor

```csharp
FileSearch searcher = new FileSearch(
    @"D:\Program Files",
    (f) => Regex.IsMatch(f.Name, @".{1,5}[Ss]ome[Pp]attern\.txt$") && f.Length >= 8192,
    tokenSource,
    ExecuteHandlers.InNewTask,
    suppressOperationCanceledException: true);
```

## Limitaciones conocidas

| Limitación | Detalle |
|------------|---------|
| Solo archivos | No incluye búsqueda de directorios (`DirectorySearch` no está en esta versión) |
| Solo Windows | Requiere .NET Framework 4.0; no corre en Linux/macOS |
| Rutas largas | En Windows, habilite `LongPathsEnabled` en el registro (`HKLM\...\FileSystem`) |
| `InNewTask` | Las excepciones no se propagan al hilo llamador; use `SearchCompleted` |
| Sin pausa | No hay `PauseSearch`/`ResumeSearch` (disponible en [NetcoreFSL](https://github.com/alanjmrt94/netcore-fsl)) |
| Junctions / symlinks | Se detectan ciclos por ruta canónica visitada; enlaces pueden listar el mismo destino una vez |

## Migración a NetcoreFSL

Si su proyecto puede usar .NET 8, considere migrar a [NetcoreFSL](https://github.com/alanjmrt94/netcore-fsl):

| Legacy (`FileSearch`) | NetcoreFSL (`FSL`) |
|-----------------------|---------------------|
| `GetFilesFast(folder, pattern)` | `new FSL(...); fsl.FileSearch();` + evento `FilesFound` |
| `Func<FileInfo, bool>` | No disponible — solo patrones |
| `FileSearchMultiple` | Una instancia `FSL` por carpeta |
| `StopSearch()` | `CancelSearch()` |
| — | `FolderSearch()`, `PauseSearch()`, multiplataforma |

## Publicación en NuGet (mantenedores)

El workflow `.github/workflows/release.yml` se ejecuta al pushear un tag `v*` (ej. `v1.0.4`):

1. Compila Release con **strong name** (`OfficialBuild=true`)
2. Empaqueta `NETFastSearchLibrary.Legacy.nuspec`
3. Publica en **nuget.org** (paquete **sin** Author Signing; nuget.org aplica **Repository Signing**)
4. Crea GitHub Release con assets

**Author Signing** (certificado Authenticode) es **opcional**: si más adelante agregás `NUGET_SIGN_CERT_PFX` y `NUGET_SIGN_CERT_PASSWORD` en GitHub, el workflow firmará el `.nupkg` automáticamente.

### Qué hacer en nuget.org (sin certificado)

1. **Cuenta:** registrarse en [nuget.org](https://www.nuget.org/) (usuario alanjmrt94 / org EMZ Apps).
2. **API Key:** [Account → API Keys](https://www.nuget.org/account/apikeys) → **Create**
   - **Glob pattern:** `NETFastSearchLibrary.Legacy` (recomendado) o `*` para todas
   - **Expiration:** 1 año (renovar después)
   - Copiar la clave → secreto GitHub `NUGET_API_KEY`
3. **Certificates:** **no hace falta** registrar certificado para publicar unsigned.
4. **Primer push:** el ID `NETFastSearchLibrary.Legacy` queda reservado para tu cuenta al subir la primera versión.

No activar «Require signing by a registered certificate» en el paquete hasta tener certificado Authenticode.

### GitHub — environment `release`

| Secreto | Obligatorio | Descripción |
|---------|-------------|-------------|
| `EMZAPPS_SNK` | Sí | `EMZApps.snk` en **base64** |
| `NUGET_API_KEY` | Sí | API key de nuget.org |
| `NUGET_SIGN_CERT_PFX` | No | `.pfx` Authenticode en base64 (futuro Author Signing) |
| `NUGET_SIGN_CERT_PASSWORD` | No | Contraseña del `.pfx` |

Crear environment: repo → **Settings** → **Environments** → **New environment** → `release`.

Exportar `EMZAPPS_SNK`:

```bash
./scripts/build-dist.sh --export-snk-base64
```

### Publicar una versión

**Opción A — GitHub Actions (recomendado):** configurar secretos en el environment `release`, actualizar versión, luego:

```bash
git tag v1.0.5 && git push origin v1.0.5
```

**Opción B — Script local (Windows):**

```powershell
copy scripts\release.env.example scripts\release.env   # completar valores
.\scripts\release.ps1 -Version 1.0.5 -EnvFile .\scripts\release.env `
  -SkipGitTag -SkipGitHubRelease   # evita doble publicación si CI también está activo
```

Solo artefactos en `dist/` (sin NuGet ni GitHub):

```powershell
.\scripts\release.ps1 -Version 1.0.5 -DistOnly
```

En Linux:

```bash
chmod +x scripts/build-dist.sh
./scripts/build-dist.sh --help
./scripts/build-dist.sh 1.0.4
```

Salida: `dist/<version>/` con DLL, XML, `.nupkg` (Windows completo) y metadatos.

## Estructura del repositorio

```
NETFastSearchLibrary/
├── .github/workflows/        # CI (unsigned) y Release (firmado + NuGet)
├── scripts/                  # release.ps1 (Windows), build-dist.sh (Linux)
├── NETFastSearchLibrary/     # Biblioteca (.NET Framework 4.0)
│   ├── fsl.ico               # Icono del ensamblado
│   ├── NETFastSearchLibrary.Legacy.nuspec
│   └── FileSearch/           # Clases de búsqueda
├── logo_base.png             # Logo para documentación
├── LICENSE                   # MIT
├── CHANGELOG.md
└── README.md
```

## Versión

La versión se define en `NETFastSearchLibrary/Properties/AssemblyInfo.cs`:

- `AssemblyVersion`: `1.0.4.0`
- `AssemblyInformationalVersion`: `1.0.4 (.NET Framework 4.0, Legacy)`

## Licencia

[MIT](LICENSE) — Copyright (c) 2021-2026 alanjmrt94 (EMZ Apps)
