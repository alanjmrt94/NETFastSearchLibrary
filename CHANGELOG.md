# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [Unreleased]

## [1.0.4] - 2026-07-05

### Added

- Helpers internos: `SearchIoHelper`, `PathHelper`, `ParallelSearchHelper`.

### Fixed

- `FileSearchMultiple` ejecuta búsquedas en varias carpetas en paralelo (antes en serie).
- Supresión centralizada de excepciones de E/S: `UnauthorizedAccessException`, `IOException`, `SecurityException`, `PathTooLongException`, `DirectoryNotFoundException`.
- Detección de ciclos en el árbol de directorios (junctions / symlinks).
- `FileSearchBase.OnSearchCompleted` maneja `AggregateException` cuando `ExecuteHandlers.InNewTask`.
- `app.manifest` sin `longPathAware` (compatible con objetivo Windows XP).

### Changed

- Clases de búsqueda internas refactorizadas para usar los helpers.
- Paralelismo acotado con `WithDegreeOfParallelism` = `Environment.ProcessorCount`.
- Mensajes de validación de argumentos en español.
- `FileEventArgs` realiza copia defensiva de la lista de archivos.
- README: requisito Visual Studio 2015+ (`nameof`); nota sobre junctions.
- Deshabilitada firma de ensamblado; eliminada referencia a `PaatyDSMApps96.pfx`.
- Eliminado `PackageReference` duplicado; restauración NuGet vía `packages.config`.
- README: sección «Compilar desde el código fuente (Windows)».

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
