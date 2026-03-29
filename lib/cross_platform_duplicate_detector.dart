import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;


enum MediaType { photo, video }

class DuplicateMedia {
  final String path; // File path for Android, asset ID for iOS
  final String thumbnailPath; // Thumbnail path for Android, base64 thumbnail for iOS
  final DateTime timestamp;
  final int size;
  bool isSelected;
  final List<DuplicateMedia> duplicates;
  final Uint8List? thumbnailData; // For iOS, decoded thumbnail data

  DuplicateMedia({
    required this.path,
    required this.thumbnailPath,
    required this.timestamp,
    required this.size,
    this.isSelected = false,
    this.duplicates = const [],
    this.thumbnailData,
  });

  // Create a copy with different properties
  DuplicateMedia copyWith({
    String? path,
    String? thumbnailPath,
    DateTime? timestamp,
    int? size,
    bool? isSelected,
    List<DuplicateMedia>? duplicates,
    Uint8List? thumbnailData,
  }) {
    return DuplicateMedia(
      path: path ?? this.path,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      timestamp: timestamp ?? this.timestamp,
      size: size ?? this.size,
      isSelected: isSelected ?? this.isSelected,
      duplicates: duplicates ?? this.duplicates,
      thumbnailData: thumbnailData ?? this.thumbnailData,
    );
  }
}

class CrossPlatformMediaDuplicateDetector {
  final int similarityThreshold;
  final int hashSize;
  static const MethodChannel _mediaChannel = MethodChannel('com.example.clean_guru/media');

  CrossPlatformMediaDuplicateDetector({
    this.similarityThreshold = 85,
    this.hashSize = 16,
  });

  // Main method to detect duplicates across platforms
  Future<Map<String, List<DuplicateMedia>>> detectDuplicates() async {
    if (Platform.isAndroid) {
      return await _detectDuplicatesAndroid();
    } else if (Platform.isIOS) {
      return await _detectDuplicatesIOS();
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }

  // Android-specific implementation using directory scanning
  Future<Map<String, List<DuplicateMedia>>> _detectDuplicatesAndroid() async {
    try {
      final List<String> directories = await _getAndroidMediaDirectories();
      final List<DuplicateMedia> allMedia = [];
      final Map<String, List<DuplicateMedia>> duplicateGroups = {};

      // First pass: Collect all media files with their basic metadata
      for (final dir in directories) {
        final directory = Directory(dir);
        try {
          if (!await directory.exists()) continue;

          final List<FileSystemEntity> files = directory.listSync(recursive: true);

          for (var file in files) {
            if (file is File && isImageFile(file.path)) {
              final stat = await file.stat();
              final media = DuplicateMedia(
                path: file.path,
                thumbnailPath: file.path,
                timestamp: stat.modified,
                size: stat.size,
                duplicates: const [],
              );
              allMedia.add(media);
            }
          }
        } catch (e) {
          print('Error accessing directory $dir: $e');
        }
      }

      // Group by size to reduce comparison space
      final sizeGroups = _groupBySize(allMedia);

      for (var sizeGroup in sizeGroups) {
        if (sizeGroup.length > 1) {
          // Group by time proximity
          final timeGroups = _groupByTimeProximity(sizeGroup);

          for (var timeGroup in timeGroups) {
            if (timeGroup.length > 1) {
              // Perform content analysis
              await _analyzePixelSimilarity(timeGroup, duplicateGroups);
            }
          }
        }
      }

      // Convert groups to DuplicateMedia structure
      final result = <DuplicateMedia>[];
      for (var group in duplicateGroups.values) {
        if (group.length > 1) {
          // Sort by time (newest first for camera photos)
          group.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Use the newest file as the original (typically best quality for photos)
          final original = group.first;
          final duplicates = group.sublist(1);

          result.add(DuplicateMedia(
            path: original.path,
            thumbnailPath: original.thumbnailPath,
            timestamp: original.timestamp,
            size: original.size,
            isSelected: original.isSelected,
            duplicates: duplicates,
          ));
        }
      }

      return {
        'photos': result,
        'videos': [], // Not handling videos in this implementation
      };
    } catch (e) {
      print('Error in Android duplicate detection: $e');
      rethrow;
    }
  }

  // iOS-specific implementation using Photos framework
  Future<Map<String, List<DuplicateMedia>>> _detectDuplicatesIOS() async {
    try {
      // Get all photo assets from iOS Photos library
      final List<dynamic>? assetsData = await _mediaChannel.invokeMethod('getPhotoAssets');

      if (assetsData == null || assetsData.isEmpty) {
        return {'photos': [], 'videos': []};
      }

      // Convert to list of DuplicateMedia
      final List<DuplicateMedia> allMedia = [];
      for (var assetData in assetsData) {
        try {
          final String id = assetData['id'];
          final String thumbnail = assetData['thumbnail'];
          final int creationTimestamp = (assetData['creationDate'] * 1000).toInt();
          final int modificationTimestamp = (assetData['modificationDate'] * 1000).toInt();
          final int size = assetData['size'];

          // Decode base64 thumbnail for display
          Uint8List? thumbnailData;
          try {
            thumbnailData = base64Decode(thumbnail);
          } catch (e) {
            print('Error decoding thumbnail: $e');
          }

          final media = DuplicateMedia(
            path: id, // Store asset ID as the path
            thumbnailPath: thumbnail, // Store base64 thumbnail
            timestamp: DateTime.fromMillisecondsSinceEpoch(creationTimestamp),
            size: size,
            duplicates: const [],
            thumbnailData: thumbnailData,
          );

          allMedia.add(media);
        } catch (e) {
          print('Error processing iOS asset: $e');
        }
      }

      // Group media by creation time first (most effective for iOS)
      final timeGroups = _groupByTimeProximityIOS(allMedia);
      final duplicateGroups = <String, List<DuplicateMedia>>{};

      // For each time group, compare images for similarity
      for (var timeGroup in timeGroups) {
        if (timeGroup.length > 1) {
          await _findIOSDuplicatesInGroup(timeGroup, duplicateGroups);
        }
      }

      // Convert groups to DuplicateMedia structure
      final result = <DuplicateMedia>[];
      for (var group in duplicateGroups.values) {
        if (group.length > 1) {
          // Sort by time (newest first)
          group.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Use the newest file as the original
          final original = group.first;
          final duplicates = group.sublist(1);

          result.add(DuplicateMedia(
            path: original.path,
            thumbnailPath: original.thumbnailPath,
            timestamp: original.timestamp,
            size: original.size,
            isSelected: original.isSelected,
            duplicates: duplicates,
            thumbnailData: original.thumbnailData,
          ));
        }
      }

      return {
        'photos': result,
        'videos': [], // Not handling videos
      };
    } catch (e) {
      print('Error in iOS duplicate detection: $e');
      return {'photos': [], 'videos': []};
    }
  }

  // Find duplicates within a time-grouped set of iOS photos
  Future<void> _findIOSDuplicatesInGroup(
      List<DuplicateMedia> group,
      Map<String, List<DuplicateMedia>> duplicateGroups
      ) async {
    // Create sets to track which assets have been processed
    final Set<String> processedPairs = {};

    for (int i = 0; i < group.length; i++) {
      for (int j = i + 1; j < group.length; j++) {
        final assetId1 = group[i].path;
        final assetId2 = group[j].path;

        // Create a unique key for this pair to avoid redundant comparisons
        final pairKey = assetId1.compareTo(assetId2) < 0
            ? '$assetId1:$assetId2'
            : '$assetId2:$assetId1';

        if (processedPairs.contains(pairKey)) {
          continue; // Skip if already processed
        }

        processedPairs.add(pairKey);

        try {
          // Call native iOS method to compare images
          final result = await _mediaChannel.invokeMethod('compareImages', {
            'asset1Id': assetId1,
            'asset2Id': assetId2,
          });

          final double similarity = result['similarity'];

          if (similarity >= similarityThreshold) {
            // Generate group hash for tracking this duplicate group
            final hash = _generateGroupHash('$assetId1:$assetId2');

            // Add both assets to the duplicate group
            duplicateGroups.putIfAbsent(hash, () => []);

            // Check if either asset is already in the group
            if (!duplicateGroups[hash]!.any((m) => m.path == assetId1)) {
              duplicateGroups[hash]!.add(group[i]);
            }

            if (!duplicateGroups[hash]!.any((m) => m.path == assetId2)) {
              duplicateGroups[hash]!.add(group[j]);
            }
          }
        } catch (e) {
          print('Error comparing iOS assets: $e');
        }
      }
    }
  }

  // Group media by time proximity (optimized for iOS)
  List<List<DuplicateMedia>> _groupByTimeProximityIOS(List<DuplicateMedia> media) {
    // For iOS, burst photos are typically taken within seconds
    const timeThreshold = Duration(seconds: 30);
    final groups = <DateTime, List<DuplicateMedia>>{};

    for (var m in media) {
      bool addedToGroup = false;
      for (var timestamp in groups.keys) {
        if (m.timestamp.difference(timestamp).abs() <= timeThreshold) {
          groups[timestamp]!.add(m);
          addedToGroup = true;
          break;
        }
      }
      if (!addedToGroup) {
        groups[m.timestamp] = [m];
      }
    }

    return groups.values.where((g) => g.length > 1).toList();
  }

  // Get Android media directories
  Future<List<String>> _getAndroidMediaDirectories() async {
    List<String> directories = [];

    try {
      // Get external storage directories
      final externalDirs = await getExternalStorageDirectories();
      if (externalDirs != null) {
        directories.addAll(externalDirs.map((dir) => dir.path));
      }

      // Add common media directories
      final storage = await getExternalStorageDirectory();
      if (storage != null) {
        final String basePath = storage.path.split('/Android')[0];
        directories.addAll([
          '$basePath/DCIM/Camera',
          '$basePath/DCIM',
          '$basePath/Pictures',
          '$basePath/Download',
        ]);
      }
    } catch (e) {
      print('Error getting media directories: $e');
    }

    return directories.where((dir) => Directory(dir).existsSync()).toList();
  }

  // Group media by size
  List<List<DuplicateMedia>> _groupBySize(List<DuplicateMedia> media) {
    final groups = <int, List<DuplicateMedia>>{};
    for (var m in media) {
      groups.putIfAbsent(m.size, () => []).add(m);
    }
    return groups.values.where((g) => g.length > 1).toList();
  }

  // Group by time proximity for Android
  List<List<DuplicateMedia>> _groupByTimeProximity(List<DuplicateMedia> media) {
    const timeThreshold = Duration(minutes: 5);
    final groups = <DateTime, List<DuplicateMedia>>{};

    for (var m in media) {
      bool addedToGroup = false;
      for (var timestamp in groups.keys) {
        if (m.timestamp.difference(timestamp).abs() <= timeThreshold) {
          groups[timestamp]!.add(m);
          addedToGroup = true;
          break;
        }
      }
      if (!addedToGroup) {
        groups[m.timestamp] = [m];
      }
    }

    return groups.values.where((g) => g.length > 1).toList();
  }

  // Android perceptual hash similarity analysis
  Future<void> _analyzePixelSimilarity(
      List<DuplicateMedia> group,
      Map<String, List<DuplicateMedia>> duplicateGroups,
      ) async {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        final similarity = await _calculateImageSimilarity(
          group[i].path,
          group[j].path,
        );

        if (similarity >= similarityThreshold) {
          final hash = _generateGroupHash(group[i].path + group[j].path);
          duplicateGroups.putIfAbsent(hash, () => []);

          // Check if either media is already in the group
          if (!duplicateGroups[hash]!.any((m) => m.path == group[i].path)) {
            duplicateGroups[hash]!.add(group[i]);
          }

          if (!duplicateGroups[hash]!.any((m) => m.path == group[j].path)) {
            duplicateGroups[hash]!.add(group[j]);
          }
        }
      }
    }
  }

  // Calculate image similarity (only for Android)
  Future<double> _calculateImageSimilarity(String path1, String path2) async {
    try {
      final hash1 = await _calculatePerceptualHash(path1);
      final hash2 = await _calculatePerceptualHash(path2);

      if (hash1 == null || hash2 == null) return 0.0;
      return _compareHashes(hash1, hash2);
    } catch (e) {
      print('Error calculating image similarity: $e');
      return 0.0;
    }
  }

  // Calculate perceptual hash (only for Android)
  Future<List<bool>?> _calculatePerceptualHash(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return null;

      // Resize to small square for hash calculation
      final resized = img.copyResize(image, width: hashSize, height: hashSize);
      final grayscale = img.grayscale(resized);
      final pixels = grayscale.getBytes();

      if (pixels.isEmpty) return null;

      // Calculate average pixel value
      int sum = 0;
      for (var i = 0; i < pixels.length; i += grayscale.numChannels) {
        sum += pixels[i]; // Only need one channel for grayscale
      }

      final avg = (sum / (hashSize * hashSize)).round();

      // Generate hash based on whether pixel is above or below average
      List<bool> hash = [];
      for (var i = 0; i < pixels.length; i += grayscale.numChannels) {
        hash.add(pixels[i] > avg);
      }

      return hash;
    } catch (e) {
      print('Error calculating perceptual hash: $e');
      return null;
    }
  }

  // Compare two hashes (only for Android)
  double _compareHashes(List<bool> hash1, List<bool> hash2) {
    if (hash1.length != hash2.length) return 0.0;

    int similarities = 0;
    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] == hash2[i]) similarities++;
    }

    return (similarities / hash1.length) * 100;
  }

  // Generate a hash for grouping similar images
  String _generateGroupHash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  // Delete a media file (cross-platform)
  Future<bool> deleteMedia(DuplicateMedia media) async {
    try {
      if (Platform.isAndroid) {
        // Android: delete the actual file
        final file = File(media.path);
        if (await file.exists()) {
          await file.delete();

          // Notify MediaStore about the deletion
          try {
            await _mediaChannel.invokeMethod('notifyMediaStoreFileDeleted', {
              'filePath': media.path
            });
          } catch (e) {
            print('Error notifying MediaStore: $e');
          }

          return true;
        }
        return false;
      } else if (Platform.isIOS) {
        // iOS: delete using PhotoKit
        final result = await _mediaChannel.invokeMethod('deleteAsset', {
          'assetId': media.path
        });
        return result == true;
      }
      return false;
    } catch (e) {
      print('Error deleting media: $e');
      return false;
    }
  }
}

// Helper functions
bool isImageFile(String filePath) {
  final ext = path.extension(filePath).toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic'].contains(ext);
}

bool isVideoFile(String filePath) {
  final ext = path.extension(filePath).toLowerCase();
  return ['.mp4', '.mov', '.avi', '.mkv', '.3gp', '.webm'].contains(ext);
}