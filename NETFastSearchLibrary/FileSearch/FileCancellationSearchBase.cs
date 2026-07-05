using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace NETFastSearchLibrary
{
  /// <summary>
  /// Base interna para búsqueda cancelable con token y supresión opcional de excepciones.
  /// </summary>
  internal abstract class FileCancellationSearchBase : FileSearchBase
  {
    protected CancellationToken token;

    protected bool SuppressOperationCanceledException { get; set; }

    public FileCancellationSearchBase(
      string folder,
      ExecuteHandlers handlerOption,
      bool suppressOperationCanceledException,
      CancellationToken token)
      : base(folder, handlerOption)
    {
      this.token = token;
      SuppressOperationCanceledException = suppressOperationCanceledException;
    }

    public override void StartSearch()
    {
      ResetVisitedDirectories();

      try
      {
        GetFilesFast();
      }
      catch (OperationCanceledException)
      {
        OnSearchCompleted(true);

        if (!SuppressOperationCanceledException)
        {
          token.ThrowIfCancellationRequested();
        }

        return;
      }

      OnSearchCompleted(false);
    }

    protected override void OnFilesFound(List<FileInfo> files)
    {
      if (handlerOption == ExecuteHandlers.InNewTask)
      {
        taskHandlers.Add(TaskEx.Run(() => CallFilesFound(files), token));
      }
      else
      {
        CallFilesFound(files);
      }
    }

    protected override void OnSearchCompleted(bool isCanceled)
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

          if (!isCanceled)
          {
            isCanceled = true;
          }
        }

        CallSearchCompleted(isCanceled);
      }
      else
      {
        CallSearchCompleted(isCanceled);
      }
    }

    protected override void GetFilesFast()
    {
      List<DirectoryInfo> startDirs = GetStartDirectories(folder);

      startDirs.AsParallel()
        .WithDegreeOfParallelism(ParallelSearchHelper.MaxDegreeOfParallelism)
        .WithCancellation(token)
        .ForAll((d) =>
        {
          GetStartDirectories(d.FullName).AsParallel()
            .WithDegreeOfParallelism(ParallelSearchHelper.MaxDegreeOfParallelism)
            .WithCancellation(token)
            .ForAll((dir) =>
            {
              GetFiles(dir.FullName);
            });
        });
    }
  }
}
