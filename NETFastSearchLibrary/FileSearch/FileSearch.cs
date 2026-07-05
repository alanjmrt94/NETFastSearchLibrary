using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace NETFastSearchLibrary
{

    /// <summary>
    /// Búsqueda recursiva rápida de archivos con métodos estáticos y API basada en eventos.
    /// </summary>
    /// <remarks>
    /// Los métodos estáticos (<see cref="GetFiles"/>, <see cref="GetFilesFast"/>, etc.) devuelven
    /// el resultado completo al finalizar. La API por instancia notifica lotes mediante
    /// <see cref="FilesFound"/> mientras la búsqueda está en curso.
    /// </remarks>
    public class FileSearch
    {
        #region Instance members

        private FileSearchBase searcher;

        private CancellationTokenSource tokenSource;

        /// <summary>
        /// Se dispara cuando se encuentra un nuevo lote de archivos.
        /// Los manejadores no son seguros entre hilos; use <c>lock</c> o colecciones de
        /// <see cref="System.Collections.Concurrent"/> namespace.
        /// </summary>
        public event EventHandler<FileEventArgs> FilesFound
        {
            add
            {
                searcher.FilesFound += value; 
            }

            remove
            {
                searcher.FilesFound -= value;
            }
        }


        /// <summary>
        /// Se dispara cuando la búsqueda finaliza o se detiene con <see cref="StopSearch"/>.
        /// </summary>
        public event EventHandler<SearchCompletedEventArgs> SearchCompleted
        {
            add
            {
                searcher.SearchCompleted += value;
            }

            remove
            {
                searcher.SearchCompleted -= value;
            }
        }


        #region FilePatternSearch constructors 

        /// <summary>
        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con patrón de búsqueda.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, string pattern, ExecuteHandlers handlerOption)
        {
            CheckFolder(folder);

            CheckPattern(pattern);
            
            searcher = new FilePatternSearch(folder, pattern, handlerOption);
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con patrón de búsqueda.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, string pattern) : this(folder, pattern, ExecuteHandlers.InCurrentTask)
        {
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> en el directorio indicado (patrón <c>*</c>).
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder) : this(folder, "*", ExecuteHandlers.InCurrentTask)
        {
        }

        #endregion


        #region FileDelegateSearch constructors


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con delegado de filtrado.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, Func<FileInfo, bool> isValid, ExecuteHandlers handlerOption)
        {
            CheckFolder(folder);

            CheckDelegate(isValid);

            searcher = new FileDelegateSearch(folder, isValid, handlerOption);
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con delegado de filtrado.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, Func<FileInfo, bool> isValid)
            : this(folder, isValid, ExecuteHandlers.InCurrentTask)
        {
        }

        #endregion


        #region FileCancellationPatternSearch constructors

        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con patrón de búsqueda y cancelación.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> que permite cancelar la búsqueda.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <param name="suppressOperationCanceledException"><c>true</c> para suprimir <see cref="OperationCanceledException"/> al cancelar; <c>false</c> para propagarla.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, string pattern, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption, bool suppressOperationCanceledException)
        {
            CheckFolder(folder);

            CheckPattern(pattern);

            CheckTokenSource(tokenSource);

            searcher = new FileCancellationPatternSearch(folder, pattern, handlerOption, suppressOperationCanceledException, tokenSource.Token);
            this.tokenSource = tokenSource;
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con patrón de búsqueda.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> que permite cancelar la búsqueda.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, string pattern, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption)
            : this(folder, pattern, tokenSource, handlerOption, true)
        {
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con patrón de búsqueda.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> que permite cancelar la búsqueda.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, string pattern, CancellationTokenSource tokenSource) 
            : this(folder, pattern, tokenSource, ExecuteHandlers.InCurrentTask, true)
        {
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> en el directorio indicado (patrón <c>*</c>).
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> que permite cancelar la búsqueda.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, CancellationTokenSource tokenSource) 
            : this(folder, "*", tokenSource, ExecuteHandlers.InCurrentTask, true)
        {
        }

        #endregion


        #region FileCancellationDelegateSearch constructors

        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con delegado de filtrado y cancelación.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> que permite cancelar la búsqueda.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <param name="suppressOperationCanceledException"><c>true</c> para suprimir <see cref="OperationCanceledException"/> al cancelar; <c>false</c> para propagarla.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, Func<FileInfo, bool> isValid, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption, bool suppressOperationCanceledException)
        {
            CheckFolder(folder);

            CheckDelegate(isValid);

            CheckTokenSource(tokenSource);

            searcher = new FileCancellationDelegateSearch(folder, isValid, handlerOption, suppressOperationCanceledException, tokenSource.Token);
            this.tokenSource = tokenSource;
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con delegado de filtrado y cancelación.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> que permite cancelar la búsqueda.</param>
        /// <param name="handlerOption">Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, Func<FileInfo, bool> isValid, CancellationTokenSource tokenSource, ExecuteHandlers handlerOption)
            : this(folder, isValid, tokenSource, handlerOption, true)
        { 
        }


        /// <summary>
        /// Inicializa una nueva instancia de <see cref="FileSearch"/> con delegado de filtrado y cancelación.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <param name="tokenSource"><see cref="CancellationTokenSource"/> que permite cancelar la búsqueda.</param>
        /// <exception cref="ArgumentException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        public FileSearch(string folder, Func<FileInfo, bool> isValid, CancellationTokenSource tokenSource)
            : this(folder, isValid, tokenSource, ExecuteHandlers.InCurrentTask, true)
        {
        }

        #endregion


        #region Checking methods

        private void CheckFolder(string folder)
        {
            if (folder == null)
                throw new ArgumentNullException("folder", "El argumento no puede ser nulo.");

            if (string.IsNullOrEmpty(folder))
                throw new ArgumentException("El argumento no es válido.", "folder");

            DirectoryInfo dir = new DirectoryInfo(folder);

            if (!dir.Exists)
                throw new ArgumentException("El argumento no representa un directorio existente.", "folder");
        }


        private void CheckPattern(string pattern)
        {
            if (pattern == null)
                throw new ArgumentNullException("pattern", "El argumento no puede ser nulo.");

            if (string.IsNullOrEmpty(pattern))
                throw new ArgumentException("El argumento no es válido.", "pattern");
        }


        private void CheckDelegate(Func<FileInfo, bool> isValid)
        {
            if (isValid == null)
                throw new ArgumentNullException("isValid", "El argumento no puede ser nulo.");
        }


        private void CheckTokenSource(CancellationTokenSource tokenSource)
        {
            if (tokenSource == null)
                throw new ArgumentNullException("tokenSource", "El argumento no puede ser nulo.");
        }
 

        #endregion


        /// <summary>
        /// Inicia la búsqueda con notificación en tiempo real usando el pool de hilos.
        /// </summary>
        public void StartSearch()
        {
            searcher.StartSearch();
        }


        /// <summary>
        /// Inicia la búsqueda de forma asíncrona con notificación en tiempo real.
        /// </summary>
        /// <returns>Tarea que representa la operación de búsqueda.</returns>
        public Task StartSearchAsync()
        {
            if (searcher is FileCancellationSearchBase)
            {
                return TaskEx.Run(() =>
                {
                   StartSearch();
                    
                }, tokenSource.Token);
            }

            return TaskEx.Run(() =>
            {
                StartSearch();
            });
        }


        /// <summary>
        /// Detiene la búsqueda en curso. Requiere un constructor con <see cref="CancellationTokenSource"/>.
        /// </summary>
        /// <exception cref="InvalidOperationException">Si la instancia no admite cancelación.</exception>
        public void StopSearch()
        {
            if (tokenSource == null)
                throw new InvalidOperationException("No es posible detener la búsqueda sin un CancellationTokenSource.");

            tokenSource.Cancel();
        }

        #endregion


        #region Static members

        #region Public members


        /// <summary>
        /// Busca archivos de forma recursiva en un solo hilo y devuelve la lista completa.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <returns>Lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public List<FileInfo> GetFiles(string folder, string pattern = "*")
        {
            ConcurrentDictionary<string, byte> visited = new ConcurrentDictionary<string, byte>();
            return GetFiles(folder, pattern, visited);
        }

        static private List<FileInfo> GetFiles(string folder, string pattern, ConcurrentDictionary<string, byte> visited)
        {
            if (!visited.TryAdd(PathHelper.GetCanonicalKey(folder), 0))
            {
                return new List<FileInfo>();
            }

            DirectoryInfo dirInfo;
            DirectoryInfo[] directories;

            if (!SearchIoHelper.TryGetDirectories(folder, out dirInfo, out directories))
            {
                return new List<FileInfo>();
            }

            if (directories.Length == 0)
            {
                return SearchIoHelper.RunIgnoringIo(
                    () => new List<FileInfo>(dirInfo.GetFiles(pattern)),
                    new List<FileInfo>());
            }

            List<FileInfo> result = new List<FileInfo>();

            foreach (DirectoryInfo d in directories)
            {
                result.AddRange(GetFiles(d.FullName, pattern, visited));
            }

            SearchIoHelper.RunIgnoringIo(() => result.AddRange(dirInfo.GetFiles(pattern)));
            return result;
        }



        /// <summary>
        /// Busca archivos de forma recursiva en un solo hilo usando un delegado de filtrado.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <returns>Lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public List<FileInfo> GetFiles(string folder, Func<FileInfo, bool> isValid)
        {
            ConcurrentDictionary<string, byte> visited = new ConcurrentDictionary<string, byte>();
            return GetFiles(folder, isValid, visited);
        }

        static private List<FileInfo> GetFiles(string folder, Func<FileInfo, bool> isValid, ConcurrentDictionary<string, byte> visited)
        {
            if (!visited.TryAdd(PathHelper.GetCanonicalKey(folder), 0))
            {
                return new List<FileInfo>();
            }

            DirectoryInfo dirInfo;
            DirectoryInfo[] directories;

            if (!SearchIoHelper.TryGetDirectories(folder, out dirInfo, out directories))
            {
                return new List<FileInfo>();
            }

            if (directories.Length == 0)
            {
                return CollectFiles(dirInfo, isValid);
            }

            List<FileInfo> resultFiles = new List<FileInfo>();

            foreach (DirectoryInfo d in directories)
            {
                resultFiles.AddRange(GetFiles(d.FullName, isValid, visited));
            }

            resultFiles.AddRange(CollectFiles(dirInfo, isValid));
            return resultFiles;
        }

        static private List<FileInfo> CollectFiles(DirectoryInfo dirInfo, Func<FileInfo, bool> isValid)
        {
            return SearchIoHelper.RunIgnoringIo(() =>
            {
                List<FileInfo> resultFiles = new List<FileInfo>();
                FileInfo[] files = dirInfo.GetFiles();

                foreach (FileInfo file in files)
                {
                    if (isValid(file))
                    {
                        resultFiles.Add(file);
                    }
                }

                return resultFiles;
            }, new List<FileInfo>());
        }



        /// <summary>
        /// Busca archivos de forma recursiva en un solo hilo de manera asíncrona.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <returns>Tarea con la lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public Task<List<FileInfo>> GetFilesAsync(string folder, string pattern = "*")
        {
            return TaskEx.Run<List<FileInfo>>(() =>
            {
                return GetFiles(folder, pattern);
            });
        }



        /// <summary>
        /// Busca archivos de forma recursiva en un solo hilo de manera asíncrona usando un delegado.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <returns>Tarea con la lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public Task<List<FileInfo>> GetFilesAsync(string folder, Func<FileInfo, bool> isValid)
        {
            return TaskEx.Run<List<FileInfo>>(() =>
            {
                return GetFiles(folder, isValid);
            });
        }



        /// <summary>
        /// Busca archivos de forma recursiva usando el pool de hilos (más rápido en CPUs multinúcleo).
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <returns>Lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public List<FileInfo> GetFilesFast(string folder, string pattern = "*")
        {
            ConcurrentBag<FileInfo> files = new ConcurrentBag<FileInfo>();
            ConcurrentDictionary<string, byte> visited = new ConcurrentDictionary<string, byte>();

            List<DirectoryInfo> startDirs = GetStartDirectories(folder, files, pattern, visited);
            int parallelism = ParallelSearchHelper.MaxDegreeOfParallelism;

            startDirs.AsParallel().WithDegreeOfParallelism(parallelism).ForAll((d) =>
            {
                GetStartDirectories(d.FullName, files, pattern, visited).AsParallel()
                    .WithDegreeOfParallelism(parallelism)
                    .ForAll((dir) =>
                    {
                        foreach (FileInfo f in GetFiles(dir.FullName, pattern, visited))
                        {
                            files.Add(f);
                        }
                    });
            });

            return files.ToList();
        }



        /// <summary>
        /// Busca archivos de forma recursiva usando el pool de hilos y un delegado de filtrado.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <returns>Lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public List<FileInfo> GetFilesFast(string folder, Func<FileInfo, bool> isValid)
        {
            ConcurrentBag<FileInfo> files = new ConcurrentBag<FileInfo>();
            ConcurrentDictionary<string, byte> visited = new ConcurrentDictionary<string, byte>();

            List<DirectoryInfo> startDirs = GetStartDirectories(folder, files, isValid, visited);
            int parallelism = ParallelSearchHelper.MaxDegreeOfParallelism;

            startDirs.AsParallel().WithDegreeOfParallelism(parallelism).ForAll((d) =>
            {
                GetStartDirectories(d.FullName, files, isValid, visited).AsParallel()
                    .WithDegreeOfParallelism(parallelism)
                    .ForAll((dir) =>
                    {
                        foreach (FileInfo f in GetFiles(dir.FullName, isValid, visited))
                        {
                            files.Add(f);
                        }
                    });
            });

            return files.ToList();
        }



        /// <summary>
        /// Busca archivos de forma recursiva en el pool de hilos de manera asíncrona.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="pattern">Patrón de búsqueda (comodines <c>*</c> y <c>?</c>).</param>
        /// <returns>Tarea con la lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public Task<List<FileInfo>> GetFilesFastAsync(string folder, string pattern = "*")
        {
            return TaskEx.Run<List<FileInfo>>(() =>
            {
                return GetFilesFast(folder, pattern);
            });
        }



        /// <summary>
        /// Busca archivos de forma recursiva en el pool de hilos de manera asíncrona usando un delegado.
        /// </summary>
        /// <param name="folder">Directorio raíz donde comienza la búsqueda.</param>
        /// <param name="isValid">Delegado que determina si un archivo se incluye en el resultado.</param>
        /// <returns>Tarea con la lista de archivos encontrados.</returns>
        /// <exception cref="DirectoryNotFoundException"></exception>
        /// <exception cref="ArgumentNullException"></exception>
        static public Task<List<FileInfo>> GetFilesFastAsync(string folder, Func<FileInfo, bool> isValid)
        {
            return TaskEx.Run<List<FileInfo>>(() =>
            {
                return GetFilesFast(folder, isValid);
            });
        }


        #endregion

        #region Private members

        static private List<DirectoryInfo> GetStartDirectories(
            string folder,
            ConcurrentBag<FileInfo> files,
            string pattern,
            ConcurrentDictionary<string, byte> visited)
        {
            if (!visited.TryAdd(PathHelper.GetCanonicalKey(folder), 0))
            {
                return new List<DirectoryInfo>();
            }

            DirectoryInfo dirInfo;
            DirectoryInfo[] directories;

            if (!SearchIoHelper.TryGetDirectories(folder, out dirInfo, out directories))
            {
                return new List<DirectoryInfo>();
            }

            SearchIoHelper.RunIgnoringIo(() =>
            {
                foreach (FileInfo f in dirInfo.GetFiles(pattern))
                {
                    files.Add(f);
                }
            });

            if (directories.Length > 1)
            {
                return new List<DirectoryInfo>(directories);
            }

            if (directories.Length == 0)
            {
                return new List<DirectoryInfo>();
            }

            return GetStartDirectories(directories[0].FullName, files, pattern, visited);
        }



        static private List<DirectoryInfo> GetStartDirectories(
            string folder,
            ConcurrentBag<FileInfo> resultFiles,
            Func<FileInfo, bool> isValid,
            ConcurrentDictionary<string, byte> visited)
        {
            if (!visited.TryAdd(PathHelper.GetCanonicalKey(folder), 0))
            {
                return new List<DirectoryInfo>();
            }

            DirectoryInfo dirInfo;
            DirectoryInfo[] directories;

            if (!SearchIoHelper.TryGetDirectories(folder, out dirInfo, out directories))
            {
                return new List<DirectoryInfo>();
            }

            SearchIoHelper.RunIgnoringIo(() =>
            {
                foreach (FileInfo file in dirInfo.GetFiles())
                {
                    if (isValid(file))
                    {
                        resultFiles.Add(file);
                    }
                }
            });

            if (directories.Length > 1)
            {
                return new List<DirectoryInfo>(directories);
            }

            if (directories.Length == 0)
            {
                return new List<DirectoryInfo>();
            }

            return GetStartDirectories(directories[0].FullName, resultFiles, isValid, visited);
        }

        #endregion

        #endregion

    }
}
