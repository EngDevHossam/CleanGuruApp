

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class StorageHelper {

  static Future<Map<String, int>> getStorageInfo() async {
    try {
      if (Platform.isAndroid) {
        Directory? directory = await getExternalStorageDirectory();
        if (directory == null) {
          directory = await getApplicationDocumentsDirectory();
        }

        final FileStat stat = directory.statSync();
        final int totalBytes = stat.size;

        try {
          final result = await Process.run('df', [directory.path]);
          if (result.exitCode == 0) {
            final lines = result.stdout.toString().split('\n');
            if (lines.length > 1) {
              final parts = lines[1].split(RegExp(r'\s+'));
              if (parts.length >= 4) {
                final total = int.tryParse(parts[1]) ?? 0;
                final used = int.tryParse(parts[2]) ?? 0;
                final free = int.tryParse(parts[3]) ?? 0;

                return {
                  'total': total * 1024, // Convert to bytes
                  'used': used * 1024,
                  'free': free * 1024,
                };
              }
            }
          }
        } catch (e) {
          print('Error getting detailed storage info: $e');
        }

        // Fallback to basic info
        return {
          'total': totalBytes,
          'used': totalBytes ~/ 2, // Approximate
          'free': totalBytes ~/ 2,  // Approximate
        };
      } else {
        // iOS implementation
        final directory = await getApplicationDocumentsDirectory();
        final FileStat stat = directory.statSync();
        final freeSpace = await _getFreeDiskSpace(directory);

        return {
          'total': stat.size + freeSpace,
          'used': stat.size,
          'free': freeSpace,
        };
      }

    } catch (e) {
      print('Error getting storage info: $e');
      return {'total': 0, 'used': 0, 'free': 0};
    }

  }

  static Future<int> _getFreeDiskSpace(Directory directory) async {
    try {
      if (Platform.isAndroid) {
        final result = await Process.run('df', [directory.path]);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              return (int.tryParse(parts[3]) ?? 0) * 1024; // Convert to bytes
            }
          }
        }
      }

      // Return an approximation if we can't get actual free space
      final FileStat stat = directory.statSync();
      return stat.size ~/ 2;
    } catch (e) {
      print('Error getting free disk space: $e');
      return 0;
    }
  }

}