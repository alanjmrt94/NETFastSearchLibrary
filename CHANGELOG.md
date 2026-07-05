# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

### Fixed

- `NETFastSearchLibrary.Legacy.nuspec`: empaquetado NuGet en Linux (`target=""` provocaba `entryName` vacío); rutas con `/`.


- `build-dist.sh`: menú interactivo por defecto; release completo y comandos CLI (`--release`, `--pack`, `--push-nuget`, etc.).

## [1.0.4] - 2026-07-05

### Added

- Helpers internos: `SearchIoHelper`, `PathHelper`, `ParallelSearchHelper`.
- GitHub Actions: `ci.yml` (build Release unsigned en PR/push) y `release.yml` (strong-name + pack + push NuGet + GitHub Release en tag `v*`).
- `NETFastSearchLibrary.Legacy.nuspec` para publicación en [nuget.org](https://www.nuget.org/packages/NETFastSearchLibrary.Legacy).
- Scripts de release: `scripts/release.ps1` (Windows), `scripts/build-dist.sh` (Linux), `scripts/release.env.example`.
- Exportación base64 de claves (`--export-snk-base64`, `--export-pfx-base64`) para secretos de CI; archivos `*_base64` en `.gitignore`.
- Strong-name oficial `EMZApps.snk` (token `a8ab9e59c05f5f54`); firma solo con `OfficialBuild=true` (CI / mantenedores).

### Fixed

- `FileSearchMultiple` ejecuta búsquedas en varias carpetas en paralelo (antes en serie).
- Supresión centralizada de excepciones de E/S: `UnauthorizedAccessException`, `IOException`, `SecurityException`, `PathTooLongException`, `DirectoryNotFoundException`.
- Detección de ciclos en el árbol de directorios (junctions / symlinks).
- `FileSearchBase.OnSearchCompleted` maneja `AggregateException` cuando `ExecuteHandlers.InNewTask`.
- `app.manifest` sin `longPathAware` (compatible con objetivo Windows XP).
- Comentarios XML en `FileSearch`: `cref` ambiguos en `GetFiles`/`GetFilesFast` y `<summary>` duplicado en constructor.

### Changed

- Clases de búsqueda internas refactorizadas para usar los helpers.
- Paralelismo acotado con `WithDegreeOfParallelism` = `Environment.ProcessorCount`.
- Mensajes de validación de argumentos en español.
- `FileEventArgs` realiza copia defensiva de la lista de archivos.
- Firma de ensamblado: reemplaza certificado legacy `PaatyDSMApps96.pfx` por strong-name `EMZApps.snk` (no versionado).
- Release CI y `release.ps1`: NuGet Author Signing **opcional**; publicación por defecto unsigned (Repository Signing en nuget.org).
- `NETFastSearchLibrary.csproj`: documentación XML en configuración Release; firma condicional `OfficialBuild`.
- README: requisito Visual Studio 2015+; compilación local vs oficial; instalación NuGet; guía de secretos GitHub/nuget.org.
- `.gitignore`: `*.snk`, `*_base64`, `scripts/release.env`, `dist/`.
- Eliminado `PackageReference` duplicado; restauración NuGet vía `packages.config`.

### Removed

- Referencia a `PaatyDSMApps96.pfx` y `SignAssembly` permanente en el `.csproj`.

## [1.0.3] - 2026-07-05

### Added

- `CHANGELOG.md` y metadatos de proyecto (autor alanjmrt94 / EMZ Apps).
- Aviso de versión legacy y enlace al sucesor [NetcoreFSL](https://github.com/alanjmrt94/netcore-fsl).
- Tapa de presentación en `README.md` con `logo_base.png`.
- Comentarios XML (`///`) de la API pública en español.

### Changed

- `README.md` reescrito: marca Legacy, API documentada con nombres reales (`FileSearch`, `FileSearchMultiple`).
- `LICENSE` y `AssemblyInfo.cs`: autor actualizado a alanjmrt94 / EMZ Apps (reemplaza PaatyDSM).
- `Logo.png` renombrado a `logo_base.png`; `fsl.ico` conservado como icono del ensamblado.
- `.gitignore`: excluye `.cursor/` (plan de desarrollo) y `.vscode/`.

### Removed

- Plantillas `.vscode/solution-explorer/` (no requeridas por la biblioteca).

## [1.0.2.0] - 2021

### Changed

- Paquetes NuGet actualizados.
- Licencia actualizada.

## [1.0.0.0] - 2021

### Added

- Versión inicial publicada por PaatyDSM Apps.
- Búsqueda de archivos por patrón y delegado, métodos estáticos y API por eventos.
- `FileSearchMultiple` para búsqueda en varias carpetas.
- Compatibilidad con .NET Framework 4.0 y Windows XP.
