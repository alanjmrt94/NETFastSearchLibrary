using System;
using System.IO;
using System.Security;

namespace NETFastSearchLibrary
{
    /// <summary>
    /// Manejo centralizado de excepciones de E/S durante la búsqueda recursiva.
    /// </summary>
    internal static class SearchIoHelper
    {
        /// <summary>
        /// Indica si la excepción debe suprimirse durante el recorrido del árbol.
        /// </summary>
        public static bool IsIgnorable(Exception ex)
        {
            return ex is UnauthorizedAccessException
                || ex is PathTooLongException
                || ex is DirectoryNotFoundException
                || ex is IOException
                || ex is SecurityException;
        }

        /// <summary>
        /// Ejecuta una acción suprimiendo excepciones de E/S ignorables.
        /// </summary>
        public static void RunIgnoringIo(Action action)
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                if (!IsIgnorable(ex))
                {
                    throw;
                }
            }
        }

        /// <summary>
        /// Ejecuta una función suprimiendo excepciones de E/S ignorables.
        /// </summary>
        public static T RunIgnoringIo<T>(Func<T> func, T defaultValue)
        {
            try
            {
                return func();
            }
            catch (Exception ex)
            {
                if (IsIgnorable(ex))
                {
                    return defaultValue;
                }

                throw;
            }
        }

        /// <summary>
        /// Obtiene subdirectorios de una carpeta o devuelve <c>false</c> si el acceso falla.
        /// </summary>
        public static bool TryGetDirectories(string folder, out DirectoryInfo directoryInfo, out DirectoryInfo[] subdirectories)
        {
            directoryInfo = null;
            subdirectories = null;

            try
            {
                directoryInfo = new DirectoryInfo(PathHelper.GetFullPath(folder));
                subdirectories = directoryInfo.GetDirectories();
                return true;
            }
            catch (Exception ex)
            {
                if (IsIgnorable(ex))
                {
                    return false;
                }

                throw;
            }
        }
    }
}
