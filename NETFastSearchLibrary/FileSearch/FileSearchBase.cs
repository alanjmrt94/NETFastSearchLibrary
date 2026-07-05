using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace NETFastSearchLibrary
{
  /// <summary>
  /// Clase base interna para búsqueda paralela de archivos con eventos.
  /// </summary>
  internal abstract class FileSearchBase
  {
    /// <summary>
    /// Define dónde se ejecutan los manejadores de <see cref="FilesFound"/>.
    /// </summary>
    protected ExecuteHandlers handlerOption { get; set; }

    protected string folder;

    protected ConcurrentBag<Task> taskHandlers;

    private ConcurrentDictionary<string, byte> visitedDirectories;


    public FileSearchBase(string folder, ExecuteHandlers handlerOption)
    {
      this.folder = folder;
      this.handlerOption = handlerOption;
      taskHandlers = new ConcurrentBag<Task>();
    }


    public event EventHandler<FileEventArgs> FilesFound;

    public event EventHandler<SearchCompletedEventArgs> SearchCompleted;


    /// <summary>
    /// Reinicia el conjunto de directorios visitados al iniciar una búsqueda.
    /// </summary>
    protected void ResetVisitedDirectories()
    {
      visitedDirectories = new ConcurrentDictionary<string, byte>();
    }


    /// <summary>
    /// Registra un directorio y devuelve <c>false</c> si ya fue visitado (ciclos por junctions).
    /// </summary>
    protected bool TryEnterDirectory(string path)
    {
      if (visitedDirectories == null)
      {
        ResetVisitedDirectories();
      }

      return visitedDirectories.TryAdd(PathHelper.GetCanonicalKey(path), 0);
    }


    protected virtual void GetFilesFast()
    {
      List<DirectoryInfo> startDirs = GetStartDirectories(folder);

      startDirs.AsParallel()
        .WithDegreeOfParallelism(ParallelSearchHelper.MaxDegreeOfParallelism)
        .ForAll((d) =>
        {
          GetStartDirectories(d.FullName).AsParallel()
            .WithDegreeOfParallelism(ParallelSearchHelper.MaxDegreeOfParallelism)
            .ForAll((dir) =>
            {
              GetFiles(dir.FullName);
            });
        });

      OnSearchCompleted(false);
    }


    protected virtual void OnFilesFound(List<FileInfo> files)
    {
      if (handlerOption == ExecuteHandlers.InNewTask)
      {
        taskHandlers.Add(TaskEx.Run(() => CallFilesFound(files)));
      }
      else
      {
        CallFilesFound(files);
      }
    }


    protected virtual void CallFilesFound(List<FileInfo> files)
    {
      EventHandler<FileEventArgs> handler = FilesFound;

      if (handler != null)
      {
        var arg = new FileEventArgs(files);
        handler(this, arg);
      }
    }


    protected virtual void OnSearchCompleted(bool isCanceled)
    {
      if (handlerOption == ExecuteHandlers.InNewTask)
      {
        try
        {
          Task.WaitAll(taskHandlers.ToArray());
        }
        catch (AggregateException ex)
        {
          if (!(ex.InnerException is TaskCanceledException))
          {
            throw;
          }

          isCanceled = true;
        }
      }

      CallSearchCompleted(isCanceled);
    }


    protected virtual void CallSearchCompleted(bool isCanceled)
    {
      EventHandler<SearchCompletedEventArgs> handler = SearchCompleted;

      if (handler != null)
      {
        var arg = new SearchCompletedEventArgs(isCanceled);
        handler(this, arg);
      }
    }


    protected abstract void GetFiles(string folder);


    protected abstract List<DirectoryInfo> GetStartDirectories(string folder);


    public abstract void StartSearch();
  }
}
