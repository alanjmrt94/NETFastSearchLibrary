using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace NETFastSearchLibrary
{
  internal class FileCancellationPatternSearch : FileCancellationSearchBase
  {
    private readonly string pattern;

    public FileCancellationPatternSearch(
      string folder,
      string pattern,
      ExecuteHandlers handlerOption,
      bool suppressOperationCanceledException,
      CancellationToken token)
      : base(folder, handlerOption, suppressOperationCanceledException, token)
    {
      this.pattern = pattern;
    }

    protected override void GetFiles(string folder)
    {
      token.ThrowIfCancellationRequested();

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
        NotifyFiles(dirInfo);
        return;
      }

      foreach (DirectoryInfo d in directories)
      {
        token.ThrowIfCancellationRequested();
        GetFiles(d.FullName);
      }

      token.ThrowIfCancellationRequested();
      NotifyFiles(dirInfo);
    }

    protected override List<DirectoryInfo> GetStartDirectories(string folder)
    {
      token.ThrowIfCancellationRequested();

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

      NotifyFiles(dirInfo);

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

    private void NotifyFiles(DirectoryInfo dirInfo)
    {
      SearchIoHelper.RunIgnoringIo(() =>
      {
        FileInfo[] resFiles = dirInfo.GetFiles(pattern);
        if (resFiles.Length > 0)
        {
          OnFilesFound(new List<FileInfo>(resFiles));
        }
      });
    }
  }
}
