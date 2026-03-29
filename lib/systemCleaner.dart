


import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SystemCleaner {
  // Singleton pattern
  static final SystemCleaner _instance = SystemCleaner._internal();
  factory SystemCleaner() => _instance;
  SystemCleaner._internal();

  // Function to clean junk files
  static Future<CleanupResult> cleanJunkFiles() async {
    int filesDeleted = 0;
    int bytesFreed = 0;

    try {
      // 1. Clean app cache
      int cacheResult = await _cleanAppCache();
      filesDeleted += cacheResult;

      // 2. Clean temporary files
      final tempResult = await _cleanTempFiles();
      filesDeleted += tempResult.filesDeleted;
      bytesFreed += tempResult.bytesFreed;

      // 3. Clean download cache
      final downloadResult = await _cleanDownloadCache();
      filesDeleted += downloadResult.filesDeleted;
      bytesFreed += downloadResult.bytesFreed;

      // 4. Clean log files
      final logResult = await _cleanLogFiles();
      filesDeleted += logResult.filesDeleted;
      bytesFreed += logResult.bytesFreed;

      // 5. Clean thumbnail cache
      final thumbnailResult = await _cleanThumbnailCache();
      filesDeleted += thumbnailResult.filesDeleted;
      bytesFreed += thumbnailResult.bytesFreed;

      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    } catch (e) {
      print('Error cleaning junk files: $e');
      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed, error: e.toString());
    }
  }

  // Clean application cache
  static Future<int> _cleanAppCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      return await _deleteFilesInDir(cacheDir);
    } catch (e) {
      print('Error cleaning app cache: $e');
      return 0;
    }
  }

  // Clean temporary files
  static Future<CleanupResult> _cleanTempFiles() async {
    int filesDeleted = 0;
    int bytesFreed = 0;

    try {
      // Android-specific temp directories
      if (Platform.isAndroid) {
        // Find system temp directories
        final tempDirs = [
          '/data/local/tmp',
          '/sdcard/Android/data/com.yourappackage/cache',
          '/sdcard/Android/data/com.yourappackage/files/temp',
        ];

        for (final dir in tempDirs) {
          try {
            final directory = Directory(dir);
            if (await directory.exists()) {
              final result = await _getDirectoryStats(directory);
              filesDeleted += result.filesCount;
              bytesFreed += result.totalSize;
              await _deleteFilesInDir(directory);
            }
          } catch (e) {
            // Continue to next directory if one fails
            print('Error accessing temp directory $dir: $e');
          }
        }
      }

      // iOS-specific temp directories
      if (Platform.isIOS) {
        final tempDir = await getTemporaryDirectory();
        final result = await _getDirectoryStats(tempDir);
        filesDeleted += result.filesCount;
        bytesFreed += result.totalSize;
        await _deleteFilesInDir(tempDir);
      }

      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    } catch (e) {
      print('Error cleaning temp files: $e');
      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    }
  }

  // Clean download cache
  static Future<CleanupResult> _cleanDownloadCache() async {
    int filesDeleted = 0;
    int bytesFreed = 0;

    try {
      if (Platform.isAndroid) {
        final downloadCacheDirs = [
          '/sdcard/Download/.temp',
          '/sdcard/Android/data/com.yourappackage/files/Download',
        ];

        for (final dir in downloadCacheDirs) {
          try {
            final directory = Directory(dir);
            if (await directory.exists()) {
              final result = await _getDirectoryStats(directory);
              filesDeleted += result.filesCount;
              bytesFreed += result.totalSize;
              await _deleteFilesInDir(directory);
            }
          } catch (e) {
            print('Error accessing download cache directory $dir: $e');
          }
        }
      }

      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    } catch (e) {
      print('Error cleaning download cache: $e');
      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    }
  }

  // Clean log files
  static Future<CleanupResult> _cleanLogFiles() async {
    int filesDeleted = 0;
    int bytesFreed = 0;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${appDir.path}/logs');

      if (await logDir.exists()) {
        final result = await _getDirectoryStats(logDir);
        filesDeleted += result.filesCount;
        bytesFreed += result.totalSize;
        await _deleteFilesInDir(logDir);
      }

      // Clean system logs (may require root access on Android)
      if (Platform.isAndroid) {
        final systemLogDirs = [
          '/sdcard/Android/data/com.yourappackage/files/logs',
          '/data/data/com.yourappackage/files/logs',
        ];

        for (final dir in systemLogDirs) {
          try {
            final directory = Directory(dir);
            if (await directory.exists()) {
              final result = await _getDirectoryStats(directory);
              filesDeleted += result.filesCount;
              bytesFreed += result.totalSize;
              await _deleteFilesInDir(directory);
            }
          } catch (e) {
            print('Error accessing log directory $dir: $e');
          }
        }
      }

      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    } catch (e) {
      print('Error cleaning log files: $e');
      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    }
  }

  // Clean thumbnail cache
  static Future<CleanupResult> _cleanThumbnailCache() async {
    int filesDeleted = 0;
    int bytesFreed = 0;

    try {
      if (Platform.isAndroid) {
        final thumbnailCacheDirs = [
          '/sdcard/Android/data/com.yourappackage/files/thumbnails',
          '/sdcard/DCIM/.thumbnails',
          '/sdcard/Pictures/.thumbnails',
        ];

        for (final dir in thumbnailCacheDirs) {
          try {
            final directory = Directory(dir);
            if (await directory.exists()) {
              final result = await _getDirectoryStats(directory);
              filesDeleted += result.filesCount;
              bytesFreed += result.totalSize;
              await _deleteFilesInDir(directory);
            }
          } catch (e) {
            print('Error accessing thumbnail cache directory $dir: $e');
          }
        }
      }

      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    } catch (e) {
      print('Error cleaning thumbnail cache: $e');
      return CleanupResult(filesDeleted: filesDeleted, bytesFreed: bytesFreed);
    }
  }

  // Helper function to delete files in a directory
  static Future<int> _deleteFilesInDir(Directory directory) async {
    int count = 0;

    try {
      if (await directory.exists()) {
        final entities = await directory.list().toList();

        for (var entity in entities) {
          try {
            if (entity is File) {
              await entity.delete();
              count++;
            } else if (entity is Directory) {
              count += await _deleteFilesInDir(entity);
            }
          } catch (e) {
            print('Error deleting ${entity.path}: $e');
          }
        }
      }
    } catch (e) {
      print('Error listing directory ${directory.path}: $e');
    }

    return count;
  }

  // Helper function to get directory stats (file count and total size)
  static Future<DirectoryStats> _getDirectoryStats(Directory directory) async {
    int filesCount = 0;
    int totalSize = 0;

    try {
      if (await directory.exists()) {
        await for (var entity in directory.list(recursive: true)) {
          if (entity is File) {
            filesCount++;
            try {
              totalSize += await entity.length();
            } catch (e) {
              // Skip files we can't get size for
            }
          }
        }
      }
    } catch (e) {
      print('Error getting directory stats for ${directory.path}: $e');
    }

    return DirectoryStats(filesCount: filesCount, totalSize: totalSize);
  }

  // Format size to readable string
  static String formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}

// Class to hold directory statistics
class DirectoryStats {
  final int filesCount;
  final int totalSize;

  DirectoryStats({required this.filesCount, required this.totalSize});
}

// Class to hold cleanup results
class CleanupResult {
  final int filesDeleted;
  final int bytesFreed;
  final String? error;

  CleanupResult({required this.filesDeleted, required this.bytesFreed, this.error});

  String get formattedBytesFreed => SystemCleaner.formatSize(bytesFreed);
}