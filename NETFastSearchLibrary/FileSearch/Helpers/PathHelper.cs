using System;
using System.IO;

namespace NETFastSearchLibrary
{
    /// <summary>
    /// Utilidades de normalización de rutas para búsqueda en Windows.
    /// </summary>
    internal static class PathHelper
    {
        /// <summary>
        /// Obtiene la ruta absoluta para operaciones de E/S.
        /// </summary>
        public static string GetFullPath(string path)
        {
            if (string.IsNullOrEmpty(path))
            {
                return path;
            }

            return Path.GetFullPath(path);
        }

        /// <summary>
        /// Clave canónica para detectar directorios ya visitados (junctions / symlinks).
        /// </summary>
        public static string GetCanonicalKey(string path)
        {
            return GetFullPath(path).ToUpperInvariant();
        }
    }
}
