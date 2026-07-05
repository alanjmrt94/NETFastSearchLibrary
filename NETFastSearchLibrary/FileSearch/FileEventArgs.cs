using System;
using System.Collections.Generic;
using System.IO;

namespace NETFastSearchLibrary
{
    /// <summary>
    /// Proporciona datos para el evento <see cref="FileSearch.FilesFound"/>.
    /// </summary>
    public class FileEventArgs : EventArgs
    {
        /// <summary>
        /// Obtiene el lote de archivos encontrados en esta notificación.
        /// </summary>
        public List<FileInfo> Files { get; private set; }

        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileEventArgs"/>.
        /// </summary>
        /// <param name="files">Lista de archivos encontrados.</param>
        public FileEventArgs(List<FileInfo> files)
        {
            Files = files;
        }
    }
}
