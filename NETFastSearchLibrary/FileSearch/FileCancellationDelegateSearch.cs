using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace NETFastSearchLibrary
{
  internal class FileCancellationDelegateSearch : FileCancellationSearchBase
  {
    private readonly Func<FileInfo, bool> isValid;

    public FileCancellationDelegateSearch(
      string folder,
      Func<FileInfo, bool> isValid,
      ExecuteHandlers handlerOption,
      bool suppressOperationCanceledException,
      CancellationToken token)
      : base(folder, handlerOption, suppressOperationCanceledException, token)
    {
      this.isValid = isValid;
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
        CollectAndNotify(dirInfo);
        return;
      }

      foreach (DirectoryInfo d in directories)
      {
        token.ThrowIfCancellationRequested();
        GetFiles(d.FullName);
      }

      token.ThrowIfCancellationRequested();
      CollectAndNotify(dirInfo);
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
