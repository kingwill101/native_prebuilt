import 'dart:io';

/// A best-effort cross-process file lock for cache population.
///
/// Uses an exclusive file lock on a per-cache-key lock file so multiple hook
/// executions do not download/extract the same artifact concurrently.
final class CacheLock {
  CacheLock(this.lockFile);

  final File lockFile;

  /// Executes [action] while holding the exclusive lock.
  Future<T> withLock<T>(Future<T> Function() action) async {
    lockFile.parent.createSync(recursive: true);
    final raf = lockFile.openSync(mode: FileMode.write);
    try {
      await raf.lock(FileLock.exclusive);
      return await action();
    } finally {
      try {
        await raf.unlock();
      } finally {
        await raf.close();
      }
    }
  }
}
