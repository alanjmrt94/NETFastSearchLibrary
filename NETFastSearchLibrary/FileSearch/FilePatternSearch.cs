using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace NETFastSearchLibrary
{
  internal class FilePatternSearch : FileSearchBase
  {
    private readonly string pattern;

    public FilePatternSearch(string folder, string pattern, ExecuteHandlers handlerOption)
      : base(folder, handlerOption)
    {
      this.pattern = pattern;
    }

    public FilePatternSearch(string folder, string pattern)
      : this(folder, pattern, ExecuteHandlers.InCurrentTask)
    {
    }

    public FilePatternSearch(string folder)
      : this(folder, "*", ExecuteHandlers.InCurrentTask)
    {
    }

    /// <summary>
    /// Inicia la búsqueda por patrón con notificación en tiempo real.
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
        SearchIoHelper.RunIgnoringIo(() =>
        {
          FileInfo[] resFiles = dirInfo.GetFiles(pattern);
          if (resFiles.Length > 0)
          {
            OnFilesFound(new List<FileInfo>(resFiles));
          }
        });
        return;
      }

      foreach (DirectoryInfo d in directories)
      {
        GetFiles(d.FullName);
      }

      SearchIoHelper.RunIgnoringIo(() =>
      {
        FileInfo[] resFiles = dirInfo.GetFiles(pattern);
        if (resFiles.Length > 0)
        {
          OnFilesFound(new List<FileInfo>(resFiles));
        }
      });
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

      SearchIoHelper.RunIgnoringIo(() =>
      {
        FileInfo[] resFiles = dirInfo.GetFiles(pattern);
        if (resFiles.Length > 0)
        {
          OnFilesFound(new List<FileInfo>(resFiles));
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

      return GetStartDirectories(directories[0].FullName);
    }
  }
}
