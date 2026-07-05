using System;
using System.Collections.Generic;
using System.IO;

namespace NETFastSearchLibrary
{
  internal class FileDelegateSearch : FileSearchBase
  {
    private readonly Func<FileInfo, bool> isValid;

    public FileDelegateSearch(string folder, Func<FileInfo, bool> isValid, ExecuteHandlers handlerOption)
      : base(folder, handlerOption)
    {
      this.isValid = isValid;
    }

    public FileDelegateSearch(string folder, Func<FileInfo, bool> isValid)
      : this(folder, isValid, ExecuteHandlers.InCurrentTask)
    {
    }

    public FileDelegateSearch(string folder)
      : this(folder, (arg) => true, ExecuteHandlers.InCurrentTask)
    {
    }

    /// <summary>
    /// Inicia la búsqueda por delegado con notificación en tiempo real.
    /// </summary>
    public override void StartSearch()
    {
      ResetVisitedDirectories();
      GetFilesFast();
    }

    protected override void GetFiles(string folder)
    {
      if (!TryEnterDirectory(folder))
      {
        return;
      }

      DirectoryInfo dirInfo;
      DirectoryInfo[] directories;

      if (!SearchIoHelper.TryGetDirectories(folder, out dirInfo, out directories))
      {
        return;
      }

      if (directories.Length == 0)
      {
        CollectAndNotify(dirInfo);
        return;
      }

      foreach (DirectoryInfo d in directories)
      {
        GetFiles(d.FullName);
      }

      CollectAndNotify(dirInfo);
    }

    protected override List<DirectoryInfo> GetStartDirectories(string folder)
    {
      if (!TryEnterDirectory(folder))
      {
        return new List<DirectoryInfo>();
      }

      DirectoryInfo dirInfo;
      DirectoryInfo[] directories;

      if (!SearchIoHelper.TryGetDirectories(folder, out dirInfo, out directories))
      {
        return new List<DirectoryInfo>();
      }

      CollectAndNotify(dirInfo);

      if (directories.Length > 1)
      {
        return new List<DirectoryInfo>(directories);
      }

      if (directories.Length == 0)
      {
        return new List<DirectoryInfo>();
      }

      return GetStartDirectories(directories[0].FullName);
    }

    private void CollectAndNotify(DirectoryInfo dirInfo)
    {
      SearchIoHelper.RunIgnoringIo(() =>
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

        if (resultFiles.Count > 0)
        {
          OnFilesFound(resultFiles);
        }
      });
    }
  }
}
