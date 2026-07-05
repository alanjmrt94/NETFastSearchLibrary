using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace NETFastSearchLibrary
{
    /// <summary>
    /// Búsqueda recursiva rápida de archivos en varias carpetas raíz con API basada en eventos.
    /// </summary>
    /// <remarks>
    /// Agrupa varias búsquedas en una sola instancia; todos los directorios comparten los mismos
    /// manejadores de <see cref="FilesFound"/> y un único <see cref="SearchCompleted"/>.
    /// </remarks>
    public class FileSearchMultiple
    {
        private List<FileSearchBase> searchers;

        private CancellationTokenSource tokenSource;

        private bool suppressOperationCanceledException;


        /// <summary>
        /// Se dispara cuando se encuentra un nuevo lote de archivos en cualquiera de las carpetas.
        /// Los manejadores no son seguros entre hilos; use <c>lock</c> o colecciones concurrentes.
        /// </summary>
        public event EventHandler<FileEventArgs> FilesFound
        {
            add
            {
                searchers.ForEach((s) => s.FilesFound += value);
            }

            remove
            {
                searchers.ForEach((s) => s.FilesFound -= value);
            }
        }


        /// <summary>
        /// Se dispara cuando todas las búsquedas finalizan o se detienen con <see cref="StopSearch"/>.
        /// </summary>
        public event EventHandler<SearchCompletedEventArgs> SearchCompleted;



        /// <summary>
        /// Dispara el evento <see cref="SearchCompleted"/>.
        /// </summary>
        /// <param name="isCanceled"><c>true</c> si la búsqueda fue cancelada.</param>
        protected virtual void OnSearchCompleted(bool isCanceled)
        {
            EventHandler<SearchCompletedEventArgs> handler = SearchCompleted;

            if (handler != null)
            {
                var arg = new SearchCompletedEventArgs(isCanceled);

                handler(this, arg);
            }
        }


        #region FileCancellationDelegateSearch constructors

        /// <summary>
        /// Inicializa búsqueda múltiple con delegado de filtrado y cancelación.
        /// </summary>
        /// <param name="folders">Lista de directorios raíz.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> compartido para cancelar todas las búsquedas.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <param name="suppressOperationCanceledException"><c>true</c> para suprimir <see cref="OperationCanceledException"/> al cancelar.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearchMultiple(List<string> folders, Func<FileInfo, bool> isValid, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption, bool suppressOperationCanceledException)
        {
            CheckFolders(folders);

            CheckDelegate(isValid);

            CheckTokenSource(tokenSource);

            searchers = new List<FileSearchBase>();

            this.suppressOperationCanceledException = suppressOperationCanceledException;

            foreach (var folder in folders)
            {
                searchers.Add(new FileCancellationDelegateSearch(folder, isValid, handlerOption, false, tokenSource.Token));
            }
            
            this.tokenSource = tokenSource;
        }


        /// <summary>
        /// Inicializa búsqueda múltiple con delegado de filtrado y cancelación.
        /// </summary>
        /// <param name="folders">Lista de directorios raíz.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> compartido para cancelar todas las búsquedas.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearchMultiple(List<string> folders, Func<FileInfo, bool> isValid, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption)
            : this(folders, isValid, tokenSource, handlerOption, true)
        {
        }


        /// <summary>
        /// Inicializa búsqueda múltiple con delegado de filtrado y cancelación.
        /// </summary>
        /// <param name="folders">Lista de directorios raíz.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> compartido para cancelar todas las búsquedas.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearchMultiple(List<string> folders, Func<FileInfo, bool> isValid, CancellationTokenSource tokenSource)
            : this(folders, isValid, tokenSource, ExecuteHandlers.InCurrentTask, true)
        {
        }

        #endregion


        #region FileCancellationPatternSearch constructors

        /// <summary>
        /// Inicializa búsqueda múltiple con patrón de búsqueda y cancelación.
        /// </summary>
        /// <param name="folders">Lista de directorios raíz.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> compartido para cancelar todas las búsquedas.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <param name="suppressOperationCanceledException"><c>true</c> para suprimir <see cref="OperationCanceledException"/> al cancelar.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearchMultiple(List<string> folders, string pattern, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption, bool suppressOperationCanceledException)
        {
            CheckFolders(folders);

            CheckPattern(pattern);

            CheckTokenSource(tokenSource);

            searchers = new List<FileSearchBase>();

            this.suppressOperationCanceledException = suppressOperationCanceledException;

            foreach (var folder in folders)
            {
                searchers.Add(new FileCancellationPatternSearch(folder, pattern, handlerOption, false, tokenSource.Token));
            }

            this.tokenSource = tokenSource;
        }


        /// <summary>
        /// Inicializa búsqueda múltiple con patrón de búsqueda y cancelación.
        /// </summary>
        /// <param name="folders">Lista de directorios raíz.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> compartido para cancelar todas las búsquedas.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearchMultiple(List<string> folders, string pattern, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption)
            : this(folders, pattern, tokenSource, handlerOption, true)
        {
        }


        /// <summary>
        /// Inicializa búsqueda múltiple con patrón de búsqueda y cancelación.
        /// </summary>
        /// <param name="folders">Lista de directorios raíz.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> compartido para cancelar todas las búsquedas.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearchMultiple(List<string> folders, string pattern, CancellationTokenSource tokenSource) 
            : this(folders, pattern, tokenSource, ExecuteHandlers.InCurrentTask, true)
        {
        }


        /// <summary>
        /// Inicializa búsqueda múltiple en varias carpetas (patrón <c>*</c>) con cancelación.
        /// </summary>
        /// <param name="folders">Lista de directorios raíz.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> compartido para cancelar todas las búsquedas.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearchMultiple(List<string> folders, CancellationTokenSource tokenSource) 
            : this(folders, "*", tokenSource, ExecuteHandlers.InCurrentTask, true)
        {
        }

        #endregion


        #region Checking methods
        private void CheckFolders(List<string> folders)
        {
            if (folders == null)
                throw new ArgumentNullException(nameof(folders), "Argument is null.");

            if (folders.Count == 0)
                throw new ArgumentException("Argument is an empty list.", nameof(folders));

            foreach (var folder in folders)
                CheckFolder(folder);
        }

        private static void CheckFolder(string folder)
        {
            if (folder == null)
                throw new ArgumentNullException(nameof(folder), "Argument is null.");

            if (string.IsNullOrEmpty(folder))
                throw new ArgumentException("Argument is not valid.", nameof(folder));

            DirectoryInfo dir = new DirectoryInfo(folder);

            if (!dir.Exists)
                throw new ArgumentException("Argument does not represent an existing directory.", nameof(folder));
        }


        private void CheckPattern(string pattern)
        {
            if (pattern == null)
                throw new ArgumentNullException(nameof(pattern), "Argument is null.");

            if (string.IsNullOrEmpty(pattern))
                throw new ArgumentException("Argument is not valid.", nameof(pattern));
        }


        private void CheckDelegate(Func<FileInfo, bool> isValid)
        {
            if (isValid == null)
                throw new ArgumentNullException(nameof(isValid), "Argument is null.");
        }


        private void CheckTokenSource(CancellationTokenSource tokenSource)
        {
            if (tokenSource == null)
                throw new ArgumentNullException(nameof(tokenSource), "Argument is null.");
        }


        #endregion


        /// <summary>
        /// Inicia la búsqueda en todas las carpetas configuradas.
        /// </summary>
        public void StartSearch()
        {
            try
            {
                searchers.ForEach(s =>
                {
                    s.StartSearch();
                });
            }
            catch(OperationCanceledException ex)
            {
                OnSearchCompleted(true);
                if (!suppressOperationCanceledException)
                    throw;
                return;
            }

            OnSearchCompleted(false);
        }


        /// <summary>
        /// Inicia la búsqueda en todas las carpetas de forma asíncrona.
        /// </summary>
        /// <returns>Tarea que representa la operación de búsqueda.</returns>
        public Task StartSearchAsync()
        {
             return TaskEx.Run(() =>
             {
                  StartSearch();

             }, tokenSource.Token);      
        }


        /// <summary>
        /// Cancela la búsqueda en curso en todas las carpetas.
        /// </summary>
        public void StopSearch()
        {
            tokenSource.Cancel();
        }

    }
}
