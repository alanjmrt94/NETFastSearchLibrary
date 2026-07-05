# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

## [Unreleased]

### Changed

- Comentarios XML (`///`) de la API pública traducidos al español (`FileSearch`, `FileSearchMultiple`, eventos, `ExecuteHandlers`).

## [1.0.3] - 2026-07-05

### Added

- `CHANGELOG.md` y metadatos de proyecto (autor alanjmrt94 / EMZ Apps).
- Aviso de versión legacy y enlace al sucesor [NetcoreFSL](https://github.com/alanjmrt94/netcore-fsl).
- Tapa de presentación en `README.md` con `logo_base.png`.

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
