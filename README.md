# NETFastSearchLibrary (Legacy)

<table>
<tr>
<td width="220" valign="top"><img src="logo_base.png" alt="NETFastSearchLibrary" width="200"/></td>
<td valign="top">

**Versión:** `1.0.3` · **Estado:** mantenimiento mínimo (solo .NET Framework 4.0)  
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
- Visual Studio 2010+ (recomendado VS 2019/2022 para editar la solución)

## Instalación

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

## Migración a NetcoreFSL

Si su proyecto puede usar .NET 8, considere migrar a [NetcoreFSL](https://github.com/alanjmrt94/netcore-fsl):

| Legacy (`FileSearch`) | NetcoreFSL (`FSL`) |
|-----------------------|---------------------|
| `GetFilesFast(folder, pattern)` | `new FSL(...); fsl.FileSearch();` + evento `FilesFound` |
| `Func<FileInfo, bool>` | No disponible — solo patrones |
| `FileSearchMultiple` | Una instancia `FSL` por carpeta |
| `StopSearch()` | `CancelSearch()` |
| — | `FolderSearch()`, `PauseSearch()`, multiplataforma |

## Estructura del repositorio

```
NETFastSearchLibrary/
├── NETFastSearchLibrary/     # Biblioteca (.NET Framework 4.0)
│   ├── fsl.ico               # Icono del ensamblado
│   └── FileSearch/           # Clases de búsqueda
├── logo_base.png             # Logo para documentación
├── LICENSE                   # MIT
├── CHANGELOG.md
└── README.md
```

## Versión

La versión se define en `NETFastSearchLibrary/Properties/AssemblyInfo.cs`:

- `AssemblyVersion`: `1.0.3.0`
- `AssemblyInformationalVersion`: `1.0.3 (.NET Framework 4.0, Legacy)`

## Licencia

[MIT](LICENSE) — Copyright (c) 2021-2026 alanjmrt94 (EMZ Apps)
