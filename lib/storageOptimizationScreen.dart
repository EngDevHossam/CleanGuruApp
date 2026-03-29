import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:clean_guru/storageInfo.dart';
import 'package:clean_guru/systemMetrics.dart';
import 'package:clean_guru/themeprovider.dart';
import 'package:clean_guru/videoPlayer.dart';
import 'package:clean_guru/videoPlayerWidget.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'appInfo.dart';
import 'cleanMedia.dart';
import 'contactCleanUp.dart';
import 'duplicateScanMessage.dart';
import 'duplicateTab.dart';
import 'package:clean_guru/languageProvider.dart';

import 'largeFile.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart' as installed_package;
import 'package:provider/provider.dart';

enum MediaType { photo, video }

class DuplicateMedia {
  final String path;
  final String thumbnailPath;
  final DateTime timestamp;
  final int size;
  bool isSelected;
  final List<DuplicateMedia> duplicates;

  DuplicateMedia({
    required this.path,
    required this.thumbnailPath,
    required this.timestamp,
    required this.size,
    this.isSelected = false, // Set to false by default
    this.duplicates = const [],
  });
}

class MediaDuplicateDetector {
  final int similarityThreshold;
  final int hashSize;

  MediaDuplicateDetector({
    this.similarityThreshold = 95,
    this.hashSize = 16,
  });

  Future<List<DuplicateMedia>> detectDuplicates(
      List<String> directories) async {
    final List<DuplicateMedia> allMedia = [];
    final Map<String, List<DuplicateMedia>> duplicateGroups = {};

    // First pass: Collect all media files with their basic metadata
    for (final dir in directories) {
      final directory = Directory(dir);
      try {
        final List<FileSystemEntity> files =
            directory.listSync(recursive: true);

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

    // Step 1: Group by size
    final sizeGroups = _groupBySize(allMedia);

    for (var sizeGroup in sizeGroups) {
      if (sizeGroup.length > 1) {
        // Step 2: Within same-size groups, check timestamps
        final timeGroups = _groupByTimeProximity(sizeGroup);

        for (var timeGroup in timeGroups) {
          if (timeGroup.length > 1) {
            // Step 3: Check filename similarity
            final nameGroups = _groupByFileName(timeGroup);

            for (var nameGroup in nameGroups) {
              if (nameGroup.length > 1) {
                // Step 4: Perform pixel analysis for final confirmation
                await _analyzePixelSimilarity(nameGroup, duplicateGroups);
              }
            }
          }
        }
      }
    }

    // Convert groups to DuplicateMedia structure
    final result = <DuplicateMedia>[];
    for (var group in duplicateGroups.values) {
      if (group.length > 1) {
        // Use the oldest file as the original
        final original =
            group.reduce((a, b) => a.timestamp.isBefore(b.timestamp) ? a : b);

        // Create new instance with duplicates
        result.add(DuplicateMedia(
          path: original.path,
          thumbnailPath: original.thumbnailPath,
          timestamp: original.timestamp,
          size: original.size,
          isSelected: original.isSelected,
          duplicates: group.where((m) => m.path != original.path).toList(),
        ));
      }
    }

    return result;
  }

  List<List<DuplicateMedia>> _groupBySize(List<DuplicateMedia> media) {
    final groups = <int, List<DuplicateMedia>>{};
    for (var m in media) {
      groups.putIfAbsent(m.size, () => []).add(m);
    }
    return groups.values.where((g) => g.length > 1).toList();
  }

  List<List<DuplicateMedia>> _groupByTimeProximity(List<DuplicateMedia> media) {
    const timeThreshold = Duration(minutes: 1);
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

  List<List<DuplicateMedia>> _groupByFileName(List<DuplicateMedia> media) {
    final groups = <String, List<DuplicateMedia>>{};

    for (var m in media) {
      final filename = path.basenameWithoutExtension(m.path).toLowerCase();
      // Create normalized filename by removing numbers and special characters
      final normalized = filename.replaceAll(RegExp(r'[^a-z]'), '');
      if (normalized.isNotEmpty) {
        groups.putIfAbsent(normalized, () => []).add(m);
      }
    }

    return groups.values.where((g) => g.length > 1).toList();
  }

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
          duplicateGroups.putIfAbsent(hash, () => [])
            ..addAll([group[i], group[j]]);
        }
      }
    }
  }

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

  Future<List<bool>?> _calculatePerceptualHash(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return null;

      // Resize to small square for hash calculation
      final resized = img.copyResize(image, width: hashSize, height: hashSize);
      final grayscale = img.grayscale(resized);
      final pixels = grayscale.data;

      if (pixels == null) return null;

      // Calculate average pixel value using RGB values
      int sum = 0;
      for (var pixel in pixels) {
        // Calculate grayscale value using luminance formula
        int grayscaleValue =
            ((pixel.r * 0.299) + (pixel.g * 0.587) + (pixel.b * 0.114)).round();
        sum += grayscaleValue;
      }

      final avg = (sum / (hashSize * hashSize)).round();

      // Generate hash based on whether pixel is above or below average
      return pixels.map((pixel) {
        int grayscaleValue =
            ((pixel.r * 0.299) + (pixel.g * 0.587) + (pixel.b * 0.114)).round();
        return grayscaleValue > avg;
      }).toList();
    } catch (e) {
      print('Error calculating perceptual hash: $e');
      return null;
    }
  }

  double _compareHashes(List<bool> hash1, List<bool> hash2) {
    if (hash1.length != hash2.length) return 0.0;

    int similarities = 0;
    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] == hash2[i]) similarities++;
    }

    return (similarities / hash1.length) * 100;
  }

  String _generateGroupHash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }
}

bool isImageFile(String filePath) {
  final ext = path.extension(filePath).toLowerCase();
  return ['.jpg', '.jpeg', '.png', '.gif', '.bmp'].contains(ext);
}

class StorageOptimizationScreen extends StatefulWidget {
  final int? initialTabIndex;
  final LanguageProvider languageProvider; // Add this line

  const StorageOptimizationScreen({
    Key? key,
    this.initialTabIndex,
    required this.languageProvider, // Add this line
  }) : super(key: key);

  @override
  _StorageOptimizationScreenState createState() =>
      _StorageOptimizationScreenState();
}

class _StorageOptimizationScreenState extends State<StorageOptimizationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  StorageInfo? storageInfo;
  Map<String, List<DuplicateMedia>>? _cachedDuplicatesResult;
  bool _isDuplicateScanning = false;
  Future<Map<String, List<DuplicateMedia>>>? _duplicatesFuture;
  static const platform =
      MethodChannel('com.arabapps.cleangru/storage'); // Updated package name
  bool _isLoadingFiles = true;
  List<LargeFile> files = [];
  bool isLoading = true;
  static const mediaChannel =
      MethodChannel('com.arabapps.cleangru/media'); // Updated package name

  List<AppInfo> installedApps = [];

  bool isLoadingApps = true;
  String _getLocalizedText({
    required String titleEn,
    required String titleAr,
  }) {
    final languageProvider =
        Provider.of<LanguageProvider>(context, listen: false);
    return languageProvider.currentLocale.languageCode == 'en'
        ? titleEn
        : titleAr;
  }

  // Add the _getStorageInfo function here
  // Add the getStorageInfo function
  Future<void> _getStorageInfo() async {
    try {
      if (Platform.isAndroid) {
        Directory? directory = await getExternalStorageDirectory();
        if (directory != null) {
          final stat = await directory.stat();
          final totalSpace = await _getTotalSpace(directory);
          final freeSpace = await _getFreeSpace(directory);
          final usedSpace = totalSpace - freeSpace;

          setState(() {
            storageInfo = StorageInfo(
              totalSpace: totalSpace,
              usedSpace: usedSpace,
              freeSpace: freeSpace,
            );
          });
        }
      }
    } catch (e) {
      print('Error getting storage info: $e');
    }
  }

  Future<int> _getTotalSpace(Directory directory) async {
    try {
      final result = await Process.run('df', [directory.path]);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        if (lines.length > 1) {
          final parts = lines[1].split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            return int.parse(parts[1]) * 1024; // Convert to bytes
          }
        }
      }
    } catch (e) {
      print('Error getting total space: $e');
    }
    return 0;
  }

  Future<int> _getFreeSpace(Directory directory) async {
    try {
      final result = await Process.run('df', [directory.path]);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        if (lines.length > 1) {
          final parts = lines[1].split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            return int.parse(parts[3]) * 1024; // Convert to bytes
          }
        }
      }
    } catch (e) {
      print('Error getting free space: $e');
    }
    return 0;
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // For Android 10 and above
      if (await Permission.storage.request().isGranted &&
          await Permission.photos.request().isGranted &&
          await Permission.videos.request().isGranted) {
        return true;
      }

      // For Android 11+ (API 30+), also request manage external storage
      if (await DeviceInfoPlugin()
              .androidInfo
              .then((info) => info.version.sdkInt) >=
          30) {
        if (await Permission.manageExternalStorage.status.isGranted) {
          return true;
        }
        // Request manage external storage permission
        final status = await Permission.manageExternalStorage.request();
        return status.isGranted;
      }

      // Show settings dialog if permissions are permanently denied
      if (await Permission.storage.isPermanentlyDenied ||
          await Permission.photos.isPermanentlyDenied) {
        await openAppSettings();
      }

      return false;
    }
    return true; // For non-Android platforms
  }

  Future<void> _scanFiles(
      {bool largeFilesOnly = false, int minSizeInBytes = 0}) async {
    // Set loading state at beginning
    setState(() {
      _isLoadingFiles = true;
    });

    try {
      setState(() => isLoading = true);

      // Request permissions first
      bool permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        throw Exception('Storage permissions required');
      }

      List<LargeFile> allFiles = [];

      // Get app-specific directories that are accessible on emulator
      final appDocDir = await getApplicationDocumentsDirectory();
      final appCacheDir = await getTemporaryDirectory();
      final appExternalDir = await getExternalStorageDirectory();

      // Create a list of accessible directories
      final List<Directory> directories = [
        appDocDir,
        appCacheDir,
      ];

      if (appExternalDir != null) {
        directories.add(appExternalDir);

        // Try to add common subdirectories if on a real device
        try {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) directories.add(downloadDir);

          final dcimDir = Directory('/storage/emulated/0/DCIM');
          if (await dcimDir.exists()) directories.add(dcimDir);

          final documentsDir = Directory('/storage/emulated/0/Documents');
          if (await documentsDir.exists()) directories.add(documentsDir);
        } catch (e) {
          print('Could not access some common directories: $e');
        }
      }

      print('Scanning directories: ${directories.map((d) => d.path).toList()}');

      // Scan each directory
      for (var dir in directories) {
        try {
          final dirFiles =
              await _scanDirectory(dir.path, minSizeInBytes: minSizeInBytes);
          allFiles.addAll(dirFiles);
        } catch (e) {
          print('Error scanning directory ${dir.path}: $e');
        }
      }

      // Sort by size (largest first)
      allFiles.sort((a, b) => b.size.compareTo(a.size));

      setState(() {
        files = allFiles;
        isLoading = false;
        _isLoadingFiles = false; // Update loading state when done
      });

      print('Found ${allFiles.length} large files');
    } catch (e) {
      print('Error scanning files: $e');
      setState(() {
        isLoading = false;
        _isLoadingFiles = false; // Also update loading state on error
      });
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<List<LargeFile>> _scanDirectory(String directoryPath,
      {int minSizeInBytes = 0}) async {
    List<LargeFile> result = [];
    try {
      final dir = Directory(directoryPath);

      if (!await dir.exists()) {
        print('Directory does not exist: $directoryPath');
        return result;
      }

      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        try {
          if (entity is File) {
            final stat = await entity.stat();
            // Only add if larger than minimum size (default is 1MB unless specified otherwise)
            final minimumSize =
                minSizeInBytes > 0 ? minSizeInBytes : 1024 * 1024;
            if (stat.size > minimumSize) {
              // Get file type icon
              IconData fileIcon = _getFileIcon(entity.path);

              result.add(LargeFile(
                path: entity.path,
                size: stat.size,
                isFolder: false,
                isSelected: false, // Explicitly set to false
              ));
            }
          }
        } catch (e) {
          print('Error processing ${entity.path}: $e');
          continue;
        }
      }
    } catch (e) {
      print('Error scanning directory $directoryPath: $e');
    }
    return result;
  }

  IconData _getFileIcon(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
        return Icons.image;
      case '.mp4':
      case '.mov':
      case '.avi':
        return Icons.video_file;
      case '.mp3':
      case '.wav':
      case '.m4a':
        return Icons.audio_file;
      case '.doc':
      case '.docx':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<int> _calculateDirSize(Directory dir) async {
    int size = 0;
    try {
      await for (var entity in dir.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (e) {
      print('Error calculating directory size: $e');
    }
    return size;
  }

  Future<void> monitorCameraDirectory() async {
    // Get the camera directory path
    final cameraDir = Directory('/storage/emulated/0/DCIM/Camera');
    if (!await cameraDir.exists()) {
      print('Camera directory does not exist');
      return;
    }

    // Set up a periodic check for new photos
    Timer.periodic(Duration(seconds: 5), (timer) async {
      // Only check if the app is in the foreground and on the duplicates tab
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          _tabController.index == 0) {
        await checkForRecentCameraPhotos();
      }
    });
  }

  Future<void> checkForRecentCameraPhotos() async {
    if (_isDuplicateScanning)
      return; // Don't start a new scan if one is already in progress

    try {
      // Get camera directory
      final cameraDir = Directory('/storage/emulated/0/DCIM/Camera');
      if (!await cameraDir.exists()) {
        print('Camera directory does not exist');
        return;
      }

      // Get the most recent camera photo
      final files = await cameraDir.list().toList();
      final imageFiles = files
          .whereType<File>()
          .where((file) => isImageFile(file.path))
          .toList();

      // No images found
      if (imageFiles.isEmpty) return;

      // Sort by modification time (newest first)
      imageFiles.sort((a, b) {
        final statA = a.statSync();
        final statB = b.statSync();
        return statB.modified.compareTo(statA.modified);
      });

      // Get the most recent photo
      final mostRecentPhoto = imageFiles.first;
      final stat = mostRecentPhoto.statSync();

      // Check if it was taken in the last 30 seconds
      final now = DateTime.now();
      if (now.difference(stat.modified).inSeconds > 30) {
        // Not a recent photo, no need to scan
        return;
      }

      // We found a recently taken photo, so refresh the duplicates scan
      print('Recent camera photo detected: ${mostRecentPhoto.path}');
      _resetDuplicatesCache(); // Reset cache to force rescan

      // Show a notification to the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New photo detected - checking for duplicates'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error checking for recent camera photos: $e');
    }
  }

  // Implement a dedicated section for recent camera photos
  Widget _buildRecentCameraPhotosSection(List<DuplicateMedia> mediaList) {
    // Find very recent media (less than 2 minutes old)
    final now = DateTime.now();
    final recentCameraPhotos = mediaList.where((media) {
      // Check if it's from camera directory
      final isCameraPhoto = media.path.contains('/DCIM/Camera/');
      // Check if it's recent
      final isRecent = now.difference(media.timestamp).inMinutes < 2;
      // Check if it has duplicates
      final hasDuplicates = media.duplicates.isNotEmpty;

      return isCameraPhoto && isRecent && hasDuplicates;
    }).toList();

    if (recentCameraPhotos.isEmpty) {
      return SizedBox
          .shrink(); // Don't show anything if no recent camera photos
    }

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'Recent Camera Photos',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ],
          ),

          SizedBox(height: 8),

          Text(
            'We found duplicates in photos you just took. Keep the best one and delete the rest!',
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),

          SizedBox(height: 16),

          // List of recent camera photos with their duplicates
          ...recentCameraPhotos
              .map((media) => _buildCameraPhotoItem(context, media))
              .toList(),
        ],
      ),
    );
  }

  Widget _buildCameraPhotoItem(BuildContext context, DuplicateMedia media) {
    return Card(
      elevation: 0,
      color: Colors.transparent,
      margin: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time taken
          Text(
            'Taken ${_getTimeAgo(media.timestamp)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),

          SizedBox(height: 8),

          // Photos row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Best photo (with updated label)
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            File(media.path),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 5,
                        left: 5,
                        child: Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'BEST',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Best Image',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              SizedBox(width: 16),

              // Duplicates
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Similar Photos:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: media.duplicates.take(3).map((duplicate) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                Container(
                                  height: 100,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      File(duplicate.path),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Checkbox(
                                      value: duplicate.isSelected,
                                      onChanged: (value) {
                                        setState(() {
                                          duplicate.isSelected = value ?? false;
                                        });
                                      },
                                      shape: CircleBorder(),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 12),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    for (var duplicate in media.duplicates) {
                      duplicate.isSelected = true;
                    }
                  });
                },
                icon: Icon(Icons.check_circle_outline, size: 16),
                label: Text('Select All'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (media.duplicates.any((d) => d.isSelected)) {
                    _deleteSelectedDuplicatesForMedia(media);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Please select duplicates to delete'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                icon: Icon(Icons.delete_outline, size: 16),
                label: Text('Delete Selected'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 5) {
      return 'just now';
    } else if (difference.inSeconds < 60) {
      return '${difference.inSeconds} seconds ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }

  Widget _buildScanLargeFilesTab() {
    final isEnglish =
        Provider.of<LanguageProvider>(context).currentLocale.languageCode ==
            'en';

    if (_isLoadingFiles) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              isEnglish ? 'Scanning files...' : 'جاري مسح الملفات...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Original implementation when loading is done
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    // Check if any files are selected
    bool hasSelectedFiles = files.any((file) => file.isSelected);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEnglish
                        ? '${files.length} files found'
                        : 'تم العثور على ${files.length} ملف',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _toggleAllFiles(true),
                        child: Text(
                          isEnglish ? 'Select All' : 'تحديد الكل',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _toggleAllFiles(false),
                        child: Text(
                          isEnglish ? 'Deselect All' : 'إلغاء تحديد الكل',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.only(
                    bottom: hasSelectedFiles
                        ? 80
                        : 0), // Add padding at bottom when button is visible
                itemCount: files.length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) =>
                    _buildFileListItem(files[index]),
              ),
            ),
          ],
        ),

        // Delete button that appears when files are selected
        if (hasSelectedFiles)
          Positioned(
            bottom: 16,
            right: 16,
            left: 16,
            child: ElevatedButton.icon(
              onPressed: _deleteSelectedFiles,
              icon: Icon(Icons.delete, color: Colors.white),
              label: Text(
                  isEnglish ? 'Delete Selected Files' : 'حذف الملفات المحددة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, // Blue button
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }


  Widget _buildFileListItem(LargeFile file) {
    final fileName = path.basename(file.path);
    return ListTile(
      leading: Icon(
        _getFileIcon(file.path),
        color: Colors.grey,
        size: 24,
      ),
      title: Text(
        fileName,
        style: TextStyle(fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            file.path.replaceAll(fileName, ''),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _formatFileSize(file.size),
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
      trailing: Checkbox(
        value: file.isSelected,
        onChanged: (bool? value) {
          setState(() {
            file.isSelected = value ?? false;
          });
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    );
  }


  void _toggleAllFiles(bool selected) {
    setState(() {
      for (var file in files) {
        file.isSelected = selected;
      }
    });
  }


  Future<void> _deleteSelectedFiles() async {
    final isEnglish = Provider.of<LanguageProvider>(context, listen: false)
            .currentLocale
            .languageCode ==
        'en';

    try {
      // Access the files list from the state class
      final selectedFiles = files.where((file) => file.isSelected).toList();
      if (selectedFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(isEnglish ? 'No files selected' : 'لم يتم تحديد أي ملفات'),
          ),
        );
        return;
      }

      final totalSize = selectedFiles.fold(0, (sum, file) => sum + file.size);

      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isEnglish ? 'Delete Files' : 'حذف الملفات'),
          content: Text(isEnglish
              ? 'Are you sure you want to delete ${selectedFiles.length} files?\n'
                  'This will free up ${_formatFileSize(totalSize)}'
              : 'هل أنت متأكد من رغبتك في حذف ${selectedFiles.length} ملف؟\n'
                  'سيتم تحرير مساحة تخزين ${_formatFileSize(totalSize)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isEnglish ? 'Cancel' : 'إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                isEnglish ? 'Delete' : 'حذف',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(isEnglish ? 'Deleting files' : 'جاري حذف الملفات'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(isEnglish
                  ? 'Deleting ${selectedFiles.length} files...'
                  : 'جاري حذف ${selectedFiles.length} ملف...'),
            ],
          ),
        ),
      );

      int deletedCount = 0;

      for (var file in selectedFiles) {
        if (file.isFolder) {
          final dir = Directory(file.path);
          if (await dir.exists()) {
            await dir.delete(recursive: true);
            deletedCount++;
          }
        } else {
          final fileToDelete = File(file.path);
          if (await fileToDelete.exists()) {
            await fileToDelete.delete();
            deletedCount++;
          }
        }
      }

      // Dismiss progress dialog
      Navigator.of(context).pop();

      // Refresh the list with the 50MB filter
      await _scanFiles(minSizeInBytes: 50 * 1024 * 1024);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEnglish
              ? 'Successfully deleted $deletedCount files'
              : 'تم حذف $deletedCount ملف بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss progress dialog if showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error deleting files: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(isEnglish ? 'Error deleting files' : 'خطأ في حذف الملفات'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) {
      // Less than 1 MB
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      // Less than 1 GB
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }


  Future<void> _deleteSelectedDuplicates(List<DuplicateMedia> mediaList) async {
    final isEnglish = Provider.of<LanguageProvider>(context, listen: false)
            .currentLocale
            .languageCode ==
        'en';

    try {
      // Count selected duplicates
      int totalSelectedCount = 0;

      for (var media in mediaList) {
        totalSelectedCount +=
            media.duplicates.where((d) => d.isSelected).length;
      }

      if (totalSelectedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isEnglish
                  ? 'No duplicates selected'
                  : 'لم يتم تحديد أي نسخ متكررة')),
        );
        return;
      }

      // Confirm deletion
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isEnglish ? 'Delete Duplicates' : 'حذف النسخ المكررة'),
          content: Text(isEnglish
              ? 'Are you sure you want to delete $totalSelectedCount selected duplicates?'
              : 'هل أنت متأكد من رغبتك في حذف $totalSelectedCount من النسخ المكررة المحددة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isEnglish ? 'Cancel' : 'إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isEnglish ? 'Delete' : 'حذف',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(
              isEnglish ? 'Deleting duplicates' : 'جاري حذف النسخ المكررة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(isEnglish
                  ? 'Deleting $totalSelectedCount duplicates...'
                  : 'جاري حذف $totalSelectedCount من النسخ المكررة...'),
            ],
          ),
        ),
      );

      int deletedCount = 0;

      // Delete selected duplicates
      for (var media in mediaList) {
        final selectedDuplicates =
            media.duplicates.where((d) => d.isSelected).toList();

        for (var duplicate in selectedDuplicates) {
          final file = File(duplicate.path);
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      // Dismiss progress dialog
      Navigator.of(context).pop();

      // Refresh the cache to update the UI
      _resetDuplicatesCache();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEnglish
              ? 'Successfully deleted $deletedCount duplicates'
              : 'تم حذف $deletedCount من النسخ المكررة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss progress dialog if showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error deleting duplicates: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEnglish
              ? 'Error deleting duplicates: $e'
              : 'خطأ في حذف النسخ المكررة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uninstallSelectedApps() async {
    try {
      final selectedApps =
          installedApps.where((app) => app.isSelected).toList();

      if (selectedApps.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No apps selected')),
        );
        return;
      }

      // Show confirmation dialog
      final shouldUninstall = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Uninstall Apps'),
          content: Text(
            'Are you sure you want to uninstall ${selectedApps.length} apps?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Uninstall', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldUninstall != true) return;

      // Show progress indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Uninstalling apps'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Uninstalling ${selectedApps.length} apps...'),
            ],
          ),
        ),
      );

      // Keep track of which apps were successfully uninstalled
      List<String> uninstalledPackages = [];

      // Actually uninstall the apps
      for (var app in selectedApps) {
        try {
          // Use Android's package installer to uninstall the app
          final result = await InstalledApps.uninstallApp(app.packageName);
          if (result == true) {
            print('Successfully uninstalled: ${app.appName}');
            uninstalledPackages.add(app.packageName);
          } else {
            print('Failed to uninstall: ${app.appName}');
          }
        } catch (e) {
          print('Error uninstalling ${app.appName}: $e');
        }
      }

      // Dismiss progress dialog
      Navigator.of(context).pop();

      // Remove only the successfully uninstalled apps from the list
      if (uninstalledPackages.isNotEmpty) {
        setState(() {
          installedApps.removeWhere(
              (app) => uninstalledPackages.contains(app.packageName));
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Successfully uninstalled ${uninstalledPackages.length} apps'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss progress dialog if showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error during uninstallation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uninstalling apps'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _savePreservedImages();

    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    // WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<List<String>> getMediaDirectories() async {
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
        directories.addAll([
          '${storage.path}/DCIM',
          '${storage.path}/Pictures',
          '${storage.path}/Download',
        ]);
      }
    } catch (e) {
      print('Error getting media directories: $e');
    }

    return directories.where((dir) => Directory(dir).existsSync()).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
        length: 5,
        vsync: this,
        initialIndex: widget.initialTabIndex ??
            0 // Default to first tab if no index provided
        );

    _tabController.addListener(_handleTabSelection);
    _initializeApp();
    _checkUsagePermission();
    // monitorCameraDirectory();
    //WidgetsBinding.instance.addObserver(this);
    _loadPreservedImages();
  }

  Future<void> _loadPreservedImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preservedImages = prefs.getStringList('preservedBestImages') ?? [];
      final keptImages = prefs.getStringList('keepInListImages') ?? [];

      setState(() {
        _preservedBestImages = Set<String>.from(preservedImages);
        _keepInListImages = Set<String>.from(keptImages);
      });
    } catch (e) {
      print('Error loading preserved images: $e');
    }
  }

  void _savePreservedImages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('keepInListImages', _keepInListImages.toList());
    } catch (e) {
      print('Error saving preserved images: $e');
    }
  }


  void _handleTabSelection() {
    // Only process when the tab selection is complete, not during transition
    if (!_tabController.indexIsChanging) {
      print('Tab changed to: ${_tabController.index}');

      // Based on the selected tab, load the appropriate data
      switch (_tabController.index) {
        case 0: // Duplicates tab
          // Request permissions here before scanning for duplicates
          _requestPermissions().then((permissionsGranted) {
            if (permissionsGranted) {
              setState(() {});
            } else {
              // Show message that permissions are needed for this feature
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Photos access is required to scan for duplicates')),
              );
            }
          });
          break;

        case 1: // Large files tab
          // Request permissions before scanning files
          _requestPermissions().then((permissionsGranted) {
            if (permissionsGranted) {
              setState(() {
                _isLoadingFiles = true;
              });
              _scanFiles(minSizeInBytes: 50 * 1024 * 1024);
            } else {
              // Show message that permissions are needed
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Storage permissions are required to scan large files')),
              );
            }
          });
          break;

        case 2: // Apps Manager tab
          setState(() {
            isLoadingApps = true;
          });
          _loadInstalledAppsWithLastUsed();
          break;

        case 3: // Clean Media tab
          // Request permissions for this tab if needed
          _requestPermissions().then((permissionsGranted) {
            if (permissionsGranted) {
              // Add functionality for this tab
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('Media access required for this feature')),
              );
            }
          });
          break;

        case 4: // Contacts CleanUp tab
          // This tab likely needs contacts permission instead of storage
          break;
      }
    }
  }

  Future<void> _loadInstalledAppsWithLastUsed() async {
    setState(() => isLoadingApps = true);

    try {
      // Create the memory channel explicitly
      final memoryChannel = MethodChannel('com.arabapps.cleangru/memory');

      // Check permission first using memory channel
      final hasPermission =
          await memoryChannel.invokeMethod('checkUsagePermission');

      if (hasPermission != true) {
        final granted = await _requestUsagePermission();
        if (!granted) {
          setState(() => isLoadingApps = false);
          return;
        }
      }

      // Use getInstalledAppsWithLastUsed method from Kotlin side
      final appsData =
          await memoryChannel.invokeMethod('getInstalledAppsWithLastUsed');

      if (appsData == null) {
        setState(() => isLoadingApps = false);
        _loadMockUnusedApps(); // Fall back to mock data
        return;
      }

      // Check if permission needed response
      if (appsData is List &&
          appsData.isNotEmpty &&
          appsData[0] is Map &&
          appsData[0].containsKey('permissionNeeded') &&
          appsData[0]['permissionNeeded'] == true) {
        await _requestUsagePermission();
        setState(() => isLoadingApps = false);
        return;
      }

      // Process the app data
      List<AppInfo> apps = [];
      for (var appData in appsData) {
        final lastUsedTime = appData['lastUsed'];
        DateTime? lastUsed;

        if (lastUsedTime != null && lastUsedTime > 0) {
          lastUsed = DateTime.fromMillisecondsSinceEpoch(lastUsedTime);
        }

        apps.add(AppInfo(
          packageName: appData['packageName'] ?? '',
          appName: appData['appName'] ?? 'Unknown App',
          lastUsed: lastUsed,
          isSelected: false,
          isSystemApp: appData['isSystem'] ?? false,
        ));
      }

      setState(() {
        installedApps = apps;
        isLoadingApps = false;
      });
    } catch (e) {
      print('Error loading installed apps: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading apps: $e')));
      _loadMockUnusedApps(); // Fall back to mock data
      setState(() => isLoadingApps = false);
    }
  }

  Future<void> _initializeApp() async {
    // Request permissions first
    if (await _requestPermissions()) {
      // Check usage stats permission
      if (await _checkUsagePermission()) {
        // Load unused apps if on the correct tab
        if (_tabController.index == 2) {
          _loadUnusedApps();
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Storage permissions are required to proceed'),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
    }
  }

  Future<void> createTestLargeFiles() async {
    try {
      // First ensure we have permissions
      final permissionsGranted = await _requestPermissions();
      if (!permissionsGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Storage permissions required')),
        );
        return;
      }

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Creating test files'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Creating large files for testing...'),
            ],
          ),
        ),
      );

      int totalFilesCreated = 0;

      // Get app-specific directories that are accessible on emulator
      final appDocDir = await getApplicationDocumentsDirectory();
      final appCacheDir = await getTemporaryDirectory();
      final appExternalDir = await getExternalStorageDirectory();

      // Create a list of accessible directories
      final directories = [
        appDocDir.path,
        appCacheDir.path,
      ];

      if (appExternalDir != null) {
        directories.add(appExternalDir.path);
      }

      print('Creating files in directories: $directories');

      // Create different file types and sizes
      for (var dir in directories) {
        // Create test subdirectory
        final testDir = Directory('$dir/test_large_files');
        if (!await testDir.exists()) {
          await testDir.create(recursive: true);
        }

        // Create files with different extensions and sizes
        final fileTypes = [
          {'extension': '.mp4', 'size': 2}, // 2MB video file
          {'extension': '.pdf', 'size': 2}, // 2MB PDF file
          {'extension': '.jpg', 'size': 2}, // 2MB image file
          {'extension': '.zip', 'size': 2}, // 2MB archive
          {'extension': '.docx', 'size': 2}, // 2MB document
        ];

        for (var fileType in fileTypes) {
          final fileName =
              'large_file_${DateTime.now().millisecondsSinceEpoch}${fileType['extension']}';
          final filePath = '${testDir.path}/$fileName';
          final file = File(filePath);

          // Create file with specified size (in MB)
          final sizeInBytes = (fileType['size'] as int) * 1024 * 1024;

          // Create a file by writing a byte at a time - more memory efficient
          final raf = await file.open(mode: FileMode.write);

          // Write in smaller chunks to avoid memory issues
          const chunkSize = 1024 * 64; // 64KB chunks
          final buffer = List<int>.filled(chunkSize, 0);

          int remaining = sizeInBytes;
          while (remaining > 0) {
            final writeSize = remaining > chunkSize ? chunkSize : remaining;
            await raf.writeFrom(buffer, 0, writeSize);
            remaining -= writeSize;
          }

          await raf.close();

          print('Created file: $filePath with size: ${fileType['size']}MB');
          totalFilesCreated++;
        }
      }

      // Dismiss the progress dialog
      Navigator.of(context).pop();

      // Trigger file scan
      setState(() {
        _isLoadingFiles = true;
      });
      await _scanFiles();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created $totalFilesCreated test files'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss the progress dialog if showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error creating test files: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating test files: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleMediaSelection(DuplicateMedia media) {
    setState(() {
      media.isSelected = !media.isSelected;
    });
  }


  void _previewMedia(DuplicateMedia media) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isImageFile(media.path))
              Image.file(File(media.path))
            else
              VideoPlayerWidget(path: media.path),
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(path.basename(media.path)),
                  Text('${(media.size / 1024 / 1024).toStringAsFixed(1)} MB'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, List<DuplicateMedia>>> scanForDuplicatesOptimized() async {
    try {
      setState(() {
        _isDuplicateScanning = true;
      });

      // Step 1: Efficiently collect image files with basic metadata
      final List<DuplicateMedia> allMediaFiles = await _collectMediaFiles();
      if (allMediaFiles.isEmpty) {
        return {'photos': [], 'videos': []};
      }

      print('Total media files found: ${allMediaFiles.length}');

      // Step 2: Group by size first (exact matches)
      final Map<int, List<DuplicateMedia>> sizeGroups =
          _groupBySize(allMediaFiles);

      // Remove single-file size groups (no duplicates possible)
      sizeGroups.removeWhere((_, group) => group.length < 2);

      // Step 3: Process potential duplicates with progressive filtering
      final List<DuplicateMedia> photoDuplicates =
          await _findDuplicateGroups(sizeGroups);

      setState(() {
        _isDuplicateScanning = false;
      });

      return {
        'photos': photoDuplicates,
        'videos': [], // Not handling videos in this example
      };
    } catch (e) {
      setState(() {
        _isDuplicateScanning = false;
      });
      print('Error scanning for duplicates: $e');
      rethrow;
    }
  }

// Step 1: Collect image files efficiently
  Future<List<DuplicateMedia>> _collectMediaFiles() async {
    final List<DuplicateMedia> mediaFiles = [];

    // Check for permission first
    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      throw Exception('Storage permissions required');
    }

    // Common media directories
    final directoriesToCheck = [
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Download',
    ];

    // Limit file count to prevent memory issues
    int maxFilesToProcess = 200;
    int processedFiles = 0;
    bool atLeastOneDirectoryChecked = false;

    // Use a more efficient list function to reduce I/O operations
    for (String dirPath in directoriesToCheck) {
      if (processedFiles >= maxFilesToProcess) break;

      try {
        final directory = Directory(dirPath);
        if (await directory.exists()) {
          atLeastOneDirectoryChecked = true;

          // Get all files at once to reduce I/O overhead
          final List<FileSystemEntity> entities = await directory
              .list(recursive: true, followLinks: false)
              .where((entity) => entity is File && isImageFile(entity.path))
              .toList();

          // Process in batch to improve efficiency
          for (var entity in entities) {
            if (processedFiles >= maxFilesToProcess) break;

            if (entity is File) {
              // Get file stats once to avoid multiple file system calls
              final stat = await entity.stat();
              mediaFiles.add(DuplicateMedia(
                path: entity.path,
                thumbnailPath: entity.path,
                timestamp: stat.modified,
                size: stat.size,
                duplicates: const [],
              ));
              processedFiles++;
            }
          }
        }
      } catch (e) {
        print('Error accessing directory $dirPath: $e');
      }
    }

    if (!atLeastOneDirectoryChecked) {
      throw Exception('Could not access any media directories');
    }

    return mediaFiles;
  }

  Future<Map<String, List<DuplicateMedia>>> scanForDuplicates() async {
    final detector = MediaDuplicateDetector(similarityThreshold: 95);

    try {
      final permission = await Permission.storage.request();
      if (!permission.isGranted) {
        throw Exception('Storage permission required');
      }

      final directories = await getMediaDirectories();
      final duplicates = await detector.detectDuplicates(directories);

      return {
        'photos': duplicates.where((d) => isImageFile(d.path)).toList(),
        'videos': duplicates.where((d) => isVideoFile(d.path)).toList(),
      };
    } catch (e) {
      print('Error scanning for duplicates: $e');
      rethrow;
    }
  }

  Map<int, List<DuplicateMedia>> _groupBySize(List<DuplicateMedia> mediaFiles) {
    final Map<int, List<DuplicateMedia>> sizeGroups = {};

    for (var media in mediaFiles) {
      if (!sizeGroups.containsKey(media.size)) {
        sizeGroups[media.size] = [];
      }
      sizeGroups[media.size]!.add(media);
    }

    return sizeGroups;
  }

  Future<List<DuplicateMedia>> _findDuplicateGroups(
      Map<int, List<DuplicateMedia>> sizeGroups) async {
    final List<DuplicateMedia> duplicateGroups = [];

    // Cache for perceptual hashes
    final Map<String, List<bool>> hashCache = {};

    // Process each size group in parallel using compute for better CPU utilization
    await Future.wait(sizeGroups.entries.map((entry) async {
      final sizeGroup = entry.value;

      // Only process groups with potential duplicates
      if (sizeGroup.length < 2) return;

      // For very large groups, add additional filtering first
      List<List<DuplicateMedia>> filteredGroups = sizeGroup.length > 20
          ? _applyAdditionalFiltering(sizeGroup)
          : [sizeGroup];

      for (var group in filteredGroups) {
        if (group.length < 2) continue;

        // Calculate and compare perceptual hashes only for promising groups
        final duplicates = await _findSimilarImagesInGroup(group, hashCache);

        // Check if the result is valid and has duplicates
        if (duplicates != null &&
            duplicates.path.isNotEmpty &&
            duplicates.duplicates.isNotEmpty) {
          duplicateGroups.add(duplicates);
        }
      }
    }));

    return duplicateGroups;
  }

  List<List<DuplicateMedia>> _applyAdditionalFiltering(
      List<DuplicateMedia> group) {
    // Group by time proximity (files taken within similar timeframes)
    const timeThreshold = Duration(minutes: 5);
    Map<String, List<DuplicateMedia>> timeGroups = {};

    for (var media in group) {
      bool foundGroup = false;

      for (var entry in timeGroups.entries) {
        DateTime timestamp = DateTime.parse(entry.key);
        if (media.timestamp.difference(timestamp).abs() <= timeThreshold) {
          entry.value.add(media);
          foundGroup = true;
          break;
        }
      }

      if (!foundGroup) {
        timeGroups[media.timestamp.toIso8601String()] = [media];
      }
    }

    // Return only groups with potential duplicates
    return timeGroups.values.where((g) => g.length >= 2).toList();
  }



  @override
  Widget build(BuildContext context) {
    final languageProvider = widget.languageProvider;
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFFF2F9FF),
        centerTitle: true, // This centers the title

        title: Text(isEnglish ? 'Storage Optimization' : 'تحسين التخزين'
        ,  style: TextStyle(
            color: Colors.black, // Make text black
          ),),

      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            padding: EdgeInsets.zero,
            isScrollable: true,
            labelPadding: EdgeInsets.symmetric(horizontal: 15),
            indicatorPadding: EdgeInsets.zero,
            tabs: [
              Tab(text: isEnglish ? 'Duplicates' : 'النسخ المكررة'),
              Tab(text: isEnglish ? 'Scan Large Files' : 'مسح الملفات الكبيرة'),
              Tab(
                  text: isEnglish
                      ? 'Apps Manager'
                      : 'مدير التطبيقات'), // Changed from 'Unused Apps'
              Tab(text: isEnglish ? 'Clean Media' : 'تنظيف الوسائط'),
              Tab(text: isEnglish ? 'Contacts CleanUp' : 'تنظيف جهات الاتصال'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDuplicatesTab(),
                _buildScanLargeFilesTab(),
                _buildAppsManagerTab(), // Renamed from _buildUnusedAppsTab
                MediaCleanupTab(),
                ContactCleanupTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAppsManagerTab() {
    final isEnglish =
        Provider.of<LanguageProvider>(context).currentLocale.languageCode ==
            'en';

    if (isLoadingApps) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    if (installedApps.isEmpty) {
      return Center(
        child: Text(isEnglish ? 'No apps found' : 'لم يتم العثور على تطبيقات'),
      );
    }

    // Check if any apps are selected
    bool hasSelectedApps = installedApps.any((app) => app.isSelected);

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      isEnglish
                          ? '${installedApps.length} apps'
                          : '${installedApps.length} تطبيق',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _toggleAllApps(true),
                        child: Text(isEnglish ? 'Select All' : 'تحديد الكل',
                            style: TextStyle(color: Colors.blue)),
                      ),
                      TextButton(
                        onPressed: () => _toggleAllApps(false),
                        child: Text(
                            isEnglish ? 'Deselect All' : 'إلغاء تحديد الكل',
                            style: TextStyle(color: Colors.blue)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.only(
                    bottom: hasSelectedApps
                        ? 80
                        : 0), // Add padding if button is visible
                itemCount: installedApps.length,
                separatorBuilder: (context, index) => Divider(height: 1),
                itemBuilder: (context, index) {
                  return _buildAppListItem(installedApps[index]);
                },
              ),
            ),
          ],
        ),

        // Uninstall button appears only when apps are selected
        if (hasSelectedApps)
          Positioned(
            bottom: 16,
            right: 16,
            left: 16,
            child: ElevatedButton(
              onPressed: _uninstallSelectedApps,
              child: Text(isEnglish
                  ? 'Uninstall Selected Apps'
                  : 'إلغاء تثبيت التطبيقات المحددة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue, // Changed from red to blue
                minimumSize: Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }


  Future<DuplicateMedia?> _findSimilarImagesInGroup(
      List<DuplicateMedia> group, Map<String, List<bool>> hashCache) async {
    // Calculate perceptual hashes efficiently with caching
    Map<String, List<bool>> hashes = {};

    // Calculate hashes in parallel for better performance
    await Future.wait(group.map((media) async {
      // Check cache first
      if (hashCache.containsKey(media.path)) {
        hashes[media.path] = hashCache[media.path]!;
      } else {
        // Calculate and cache the hash
        final hash = await _calculatePerceptualHashEfficient(media.path);
        if (hash != null) {
          hashes[media.path] = hash;
          hashCache[media.path] = hash; // Cache for future use
        }
      }
    }));

    // Create similarity graph
    Map<String, Set<String>> similarityGraph = {};

    // Initialize graph nodes
    for (var media in group) {
      if (hashes.containsKey(media.path)) {
        similarityGraph[media.path] = {};
      }
    }

    // Find similar images using an optimized threshold approach
    final similarityThreshold = 80.0;

    for (int i = 0; i < group.length; i++) {
      final mediaA = group[i];
      final hashA = hashes[mediaA.path];

      if (hashA == null) continue;

      for (int j = i + 1; j < group.length; j++) {
        final mediaB = group[j];
        final hashB = hashes[mediaB.path];

        if (hashB == null) continue;

        // Use optimized hash comparison algorithm
        final similarity = _compareHashesOptimized(hashA, hashB);

        if (similarity >= similarityThreshold) {
          similarityGraph[mediaA.path]?.add(mediaB.path);
          similarityGraph[mediaB.path]?.add(mediaA.path);
        }
      }
    }

    // Find connected components (groups of similar images)
    Set<String> visited = {};
    List<Set<String>> components = [];

    for (var node in similarityGraph.keys) {
      if (!visited.contains(node)) {
        Set<String> component = {};
        _depthFirstSearch(node, similarityGraph, visited, component);

        if (component.length > 1) {
          components.add(component);
        }
      }
    }

    // For this group, create a DuplicateMedia object for the first component
    if (components.isNotEmpty) {
      final component = components.first;

      // Get the media objects for this component
      List<DuplicateMedia> mediaInComponent =
          group.where((media) => component.contains(media.path)).toList();

      if (mediaInComponent.length < 2) {
        return null; // Not enough duplicates found
      }

      // Sort by timestamp (newest first, since recent photos are typically better)
      mediaInComponent.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Use the newest file as the "best" original
      final original = mediaInComponent.first;
      final duplicates = mediaInComponent.sublist(1);

      // Create a DuplicateMedia with its duplicates
      return DuplicateMedia(
        path: original.path,
        thumbnailPath: original.thumbnailPath,
        timestamp: original.timestamp,
        size: original.size,
        isSelected: false,
        duplicates: duplicates,
      );
    }

    // Return null if no duplicates found
    return null;
  }

  Future<int> _calculateCacheSize() async {
    try {
      int size = 0;
      final tempDir = await getTemporaryDirectory();

      if (await tempDir.exists()) {
        // Simulate cache size calculation
        // In a real app, you would calculate the actual size of all files
        size = 1024 *
            1024 *
            (10 + Random().nextInt(50)); // Random size between 10-60 MB
      }

      return size;
    } catch (e) {
      print('Error calculating cache size: $e');
      return 1024 * 1024 * 15; // Default to 15 MB if calculation fails
    }
  }

  Future<List<bool>?> _calculatePerceptualHashEfficient(
      String imagePath) async {
    try {
      final file = File(imagePath);

      // Check if file exists first to avoid errors
      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return null;

      // Use smaller hash size (8x8) for faster processing
      const hashSize = 8;

      // Resize efficiently - use nearest neighbor for speed
      final resized = img.copyResize(image,
          width: hashSize,
          height: hashSize,
          interpolation: img.Interpolation.nearest);

      // Convert to grayscale
      final grayscale = img.grayscale(resized);
      final pixels = grayscale.data;

      if (pixels == null) return null;

      // Calculate average pixel value efficiently
      int sum = 0;
      for (var pixel in pixels) {
        // Simple average of RGB for speed
        int grayscaleValue = ((pixel.r + pixel.g + pixel.b) ~/ 3);
        sum += grayscaleValue;
      }

      final avg = (sum / pixels.length).round();

      // Generate binary hash
      return pixels.map((pixel) {
        int grayscaleValue = ((pixel.r + pixel.g + pixel.b) ~/ 3);
        return grayscaleValue > avg;
      }).toList();
    } catch (e) {
      print('Error calculating hash for $imagePath: $e');
      return null;
    }
  }

  double _compareHashesOptimized(List<bool> hash1, List<bool> hash2) {
    if (hash1.length != hash2.length) return 0.0;

    int differences = 0;
    final maxDifferences =
        (hash1.length * 0.2).ceil(); // Max differences for 80% similarity

    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) {
        differences++;

        // Early termination - no need to check further if we exceed threshold
        if (differences > maxDifferences) {
          return 0.0; // Below threshold
        }
      }
    }

    return ((hash1.length - differences) / hash1.length) * 100;
  }

  void _depthFirstSearch(String node, Map<String, Set<String>> graph,
      Set<String> visited, Set<String> component) {
    visited.add(node);
    component.add(node);

    for (var neighbor in graph[node] ?? {}) {
      if (!visited.contains(neighbor)) {
        _depthFirstSearch(neighbor, graph, visited, component);
      }
    }
  }

  Widget _buildDuplicatesTab() {
    // Only create a new future if one doesn't already exist
    _duplicatesFuture ??= _getScannedDuplicates();

    return FutureBuilder<Map<String, List<DuplicateMedia>>>(
      future: _duplicatesFuture,
      builder: (context, snapshot) {
        final isEnglish = Provider.of<LanguageProvider>(context, listen: false)
                .currentLocale
                .languageCode ==
            'en';

        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting ||
            _isDuplicateScanning) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  isEnglish
                      ? 'Scanning for duplicates...'
                      : 'جاري البحث عن النسخ المكررة...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          );
        }

        // Handle error state
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text(
                  isEnglish
                      ? 'Error scanning duplicates'
                      : 'خطأ في البحث عن النسخ المكررة',
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
                Text(
                  snapshot.error.toString(),
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _duplicatesFuture = null;
                      _cachedDuplicatesResult = null;
                    });
                  },
                  child: Text(isEnglish ? 'Try Again' : 'حاول مرة أخرى'),
                ),
              ],
            ),
          );
        }

        // Process data safely
        final data = snapshot.data!;
        final photos = data['photos'] ?? [];
        final videos = data['videos'] ?? [];

        // No duplicates found
        if (photos.isEmpty && videos.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
                SizedBox(height: 16),
                Text(
                  isEnglish
                      ? 'No duplicate media found'
                      : 'لم يتم العثور على وسائط مكررة',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _duplicatesFuture = null;
                      _cachedDuplicatesResult = null;
                    });
                  },
                  child: Text(isEnglish ? 'Rescan' : 'إعادة البحث'),
                ),
              ],
            ),
          );
        }

        // Combine all media and check for selected duplicates
        final allMedia = [...photos, ...videos];
        final hasSelectedDuplicates = allMedia.any((media) =>
            media.duplicates.any((duplicate) => duplicate.isSelected));

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _duplicatesFuture = null;
                  _cachedDuplicatesResult = null;
                });
              },
              child: ListView(
                children: [
                  // Photos section
                  if (photos.isNotEmpty)
                    _buildDuplicateMediaSection(context,
                        mediaList: photos,
                        title: isEnglish
                            ? '${photos.length} Photos with Duplicates'
                            : '${photos.length} صورة بها نسخ متكررة',
                        isPhotos: true),

                  // Videos section
                  if (videos.isNotEmpty)
                    _buildDuplicateMediaSection(context,
                        mediaList: videos,
                        title: isEnglish
                            ? '${videos.length} Videos with Duplicates'
                            : '${videos.length} فيديو به نسخ متكررة',
                        isPhotos: false),

                  // Bottom padding
                  SizedBox(height: hasSelectedDuplicates ? 80 : 16),
                ],
              ),
            ),

            // Delete button
            if (hasSelectedDuplicates)
              Positioned(
                bottom: 16,
                right: 16,
                left: 16,
                child: ElevatedButton.icon(
                  onPressed: () => _deleteSelectedDuplicates(allMedia),
                  icon: Icon(Icons.delete, color: Colors.white),
                  label: Text(isEnglish
                      ? 'Delete Selected Duplicates'
                      : 'حذف النسخ المكررة المحددة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }


  Future<void> prioritizeCameraPhotos() async {
    try {
      // Get camera directory
      final cameraDir = Directory('/storage/emulated/0/DCIM/Camera');
      if (!await cameraDir.exists()) {
        print('Camera directory does not exist');
        return;
      }

      // Get the list of files
      final files = await cameraDir.list().toList();
      final imageFiles = files
          .whereType<File>()
          .where((file) => isImageFile(file.path))
          .toList();

      // Sort by modification time (newest first)
      imageFiles.sort((a, b) {
        final statA = a.statSync();
        final statB = b.statSync();
        return statB.modified.compareTo(statA.modified);
      });

      // Get the 10 most recent photos
      final recentImages = imageFiles.take(10).toList();

      // Create perceptual hashes for all recent images
      final List<DuplicateMedia> recentMediaFiles = [];
      for (var file in recentImages) {
        final stat = file.statSync();
        recentMediaFiles.add(DuplicateMedia(
          path: file.path,
          thumbnailPath: file.path,
          timestamp: stat.modified,
          size: stat.size,
          duplicates: const [],
        ));
      }

      // Find duplicates among recent photos
      if (recentMediaFiles.length > 1) {
        final Map<String, List<bool>> imageHashes = {};

        // Calculate perceptual hashes
        for (var media in recentMediaFiles) {
          try {
            final hash = await _calculatePerceptualHash(media.path);
            if (hash != null) {
              imageHashes[media.path] = hash;
            }
          } catch (e) {
            print('Error calculating hash for ${media.path}: $e');
          }
        }

        // Compare hashes to find duplicates
        final duplicateGroups = <List<DuplicateMedia>>[];

        for (int i = 0; i < recentMediaFiles.length; i++) {
          for (int j = i + 1; j < recentMediaFiles.length; j++) {
            final mediaA = recentMediaFiles[i];
            final mediaB = recentMediaFiles[j];

            final hashA = imageHashes[mediaA.path];
            final hashB = imageHashes[mediaB.path];

            if (hashA != null && hashB != null) {
              final similarity = _compareHashes(hashA, hashB);

              if (similarity >= 85.0) {
                // Higher threshold for camera photos
                print(
                    'Found similar camera photos: ${mediaA.path} and ${mediaB.path} - Similarity: $similarity%');

                // Check if either image is already in a group
                bool added = false;
                for (var group in duplicateGroups) {
                  if (group.any(
                      (m) => m.path == mediaA.path || m.path == mediaB.path)) {
                    if (!group.any((m) => m.path == mediaA.path)) {
                      group.add(mediaA);
                    }
                    if (!group.any((m) => m.path == mediaB.path)) {
                      group.add(mediaB);
                    }
                    added = true;
                    break;
                  }
                }

                // If neither is in a group, create a new group
                if (!added) {
                  duplicateGroups.add([mediaA, mediaB]);
                }
              }
            }
          }
        }

        // Create DuplicateMedia objects for any found groups
        if (duplicateGroups.isNotEmpty) {
          // Add the result to the cached result
          _cachedDuplicatesResult ??= {
            'photos': [],
            'videos': [],
          };

          for (var group in duplicateGroups) {
            // Sort by timestamp (newest first for camera photos)
            group.sort((a, b) => b.timestamp.compareTo(a.timestamp));

            // Use the newest file as the original (best photo is usually the latest one)
            final original = group.first;
            final duplicates = group.sublist(1);

            final duplicateMedia = DuplicateMedia(
              path: original.path,
              thumbnailPath: original.thumbnailPath,
              timestamp: original.timestamp,
              size: original.size,
              isSelected: false,
              duplicates: duplicates,
            );

            // Add to cached results or replace existing entry
            bool replaced = false;
            for (int i = 0;
                i < _cachedDuplicatesResult!['photos']!.length;
                i++) {
              final existingItem = _cachedDuplicatesResult!['photos']![i];
              // If this group contains some of the same photos as an existing group, replace it
              if (group.any((m) =>
                  m.path == existingItem.path ||
                  existingItem.duplicates.any((d) => d.path == m.path))) {
                _cachedDuplicatesResult!['photos']![i] = duplicateMedia;
                replaced = true;
                break;
              }
            }

            if (!replaced) {
              _cachedDuplicatesResult!['photos']!.add(duplicateMedia);
            }
          }

          // Notify the UI to update
          setState(() {});
        }
      }
    } catch (e) {
      print('Error prioritizing camera photos: $e');
    }
  }


  String _formatSize(int bytes) {
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


  Widget _buildAppListItem(AppInfo app) {
    final isEnglish =
        Provider.of<LanguageProvider>(context).currentLocale.languageCode ==
            'en';

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[100],
        ),
        child: ClipOval(
          child: app.icon != null
              ? Image.memory(
                  Uint8List.fromList(app.icon!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(Icons.android, color: Colors.grey[600]);
                  },
                )
              : Icon(Icons.android, color: Colors.grey[600]),
        ),
      ),
      title: Text(
        app.appName,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        app.lastUsed != null
            ? isEnglish
                ? 'Last used: ${_formatLastUsedTime(app.lastUsed!)}'
                : 'آخر استخدام: ${_formatLastUsedTime(app.lastUsed!)}'
            : isEnglish
                ? 'Never used'
                : 'لم يتم استخدامه',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
      trailing: Checkbox(
        value: app.isSelected,
        onChanged: (bool? value) {
          _toggleAppSelection(app);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
    );
  }

  String _formatLastUsedTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final isEnglish = Provider.of<LanguageProvider>(context, listen: false)
            .currentLocale
            .languageCode ==
        'en';

    if (isEnglish) {
      if (difference.inDays > 365) {
        return '${(difference.inDays / 365).floor()} years ago';
      } else if (difference.inDays > 30) {
        return '${(difference.inDays / 30).floor()} months ago';
      } else if (difference.inDays > 0) {
        return '${difference.inDays} days ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hours ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minutes ago';
      } else {
        return 'Just now';
      }
    } else {
      if (difference.inDays > 365) {
        return 'منذ ${(difference.inDays / 365).floor()} سنة';
      } else if (difference.inDays > 30) {
        return 'منذ ${(difference.inDays / 30).floor()} شهر';
      } else if (difference.inDays > 0) {
        return 'منذ ${difference.inDays} يوم';
      } else if (difference.inHours > 0) {
        return 'منذ ${difference.inHours} ساعة';
      } else if (difference.inMinutes > 0) {
        return 'منذ ${difference.inMinutes} دقيقة';
      } else {
        return 'الآن';
      }
    }
  }

  Future<bool> _checkUsagePermission() async {
    try {
      // Use the memory channel instead of storage channel
      final hasPermission = await MethodChannel('com.arabapps.cleangru/memory')
          .invokeMethod('checkUsagePermission');

      if (hasPermission != true) {
        // Show permission request dialog - PROPERLY IMPLEMENTED
        final shouldRequest = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Usage Access Permission'),
              content: Text(
                  'To identify unused apps, we need permission to access app usage statistics. '
                  'Would you like to grant this permission?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Open Settings'),
                ),
              ],
            );
          },
        );

        if (shouldRequest == true) {
          // Open usage settings using the memory channel
          await MethodChannel('com.arabapps.cleangru/memory')
              .invokeMethod('openUsageSettings');
        }
        return false;
      }
      return true;
    } catch (e) {
      print('Error checking usage permission: $e');
      return false;
    }
  }

  Future<bool> _requestUsagePermission() async {
    try {
      // Create the memory channel explicitly
      final memoryChannel = MethodChannel('com.arabapps.cleangru/memory');

      // Show dialog explaining why we need permission
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Usage Access Required'),
          content: Text(
              'To show you which apps you haven\'t used in a while, Clean Guru needs permission to access app usage statistics.\n\n'
              'On the next screen, find Clean Guru in the list and toggle "Permit usage access".'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Not Now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        // Open system settings for usage access
        await memoryChannel.invokeMethod('openUsageSettings');

        // Give user time to change the setting
        await Future.delayed(Duration(seconds: 5));

        // Check again if permission is now granted
        final hasPermission =
            await memoryChannel.invokeMethod('checkUsagePermission');
        return hasPermission == true;
      }
      return false;
    } catch (e) {
      print('Error requesting usage permission: $e');
      return false;
    }
  }

  Future<void> _loadUnusedApps() async {
    setState(() => isLoadingApps = true);

    try {
      // Call the new getUnusedApps method
      final unusedApps = await getUnusedApps();

      setState(() {
        installedApps = unusedApps;
        isLoadingApps = false;
      });

      // If we got no apps and want to use mock data
      if (unusedApps.isEmpty) {
        _loadMockUnusedApps();
      }
    } catch (e) {
      print('Error loading unused apps: $e');
      // Fall back to mock data on error
      _loadMockUnusedApps();
      setState(() => isLoadingApps = false);
    }
  }

  // Add a method to load mock data when there's an issue
  void _loadMockUnusedApps() {
    print('Loading mock unused apps data');
    final now = DateTime.now();

    // Create some mock app data
    List<AppInfo> mockApps = [
      AppInfo(
        packageName: 'com.example.unusedgame',
        appName: 'Unused Game',
        lastUsed: now.subtract(Duration(days: 30)),
        isSelected: false,
        isSystemApp: false,
      ),
      AppInfo(
        packageName: 'com.example.oldchat',
        appName: 'Old Chat App',
        lastUsed: now.subtract(Duration(days: 45)),
        isSelected: false,
        isSystemApp: false,
      ),
      AppInfo(
        packageName: 'com.example.rarelyused',
        appName: 'Rarely Used Editor',
        lastUsed: now.subtract(Duration(days: 14)),
        isSelected: false,
        isSystemApp: false,
      ),
    ];

    setState(() {
      installedApps = mockApps;
      isLoadingApps = false;
    });
  }

  Future<List<AppInfo>> getUnusedApps() async {
    final platform = MethodChannel('com.arabapps.cleangru/memory');

    // First check permission
    bool? hasPermission = await platform.invokeMethod('checkUsagePermission');

    if (hasPermission != true) {
      // Request permission
      await platform.invokeMethod('openUsageSettings');
      // Wait for user to grant permission
      // You might want to show a dialog explaining what to do
      return [];
    }

    // Get unused apps
    List<dynamic> result = await platform.invokeMethod('getUnusedApps');

    List<AppInfo> unusedApps = result.map((app) {
      return AppInfo(
        packageName: app['packageName'],
        appName: app['name'],
        icon: app['icon'],
        isSelected: false,
        isSystemApp: false,
      );
    }).toList();

    return unusedApps;
  }

  String _twoDigits(int n) {
    if (n >= 10) return "$n";
    return "0$n";
  }

  Future<bool> _checkIfAppIsUnused(String? packageName) async {
    if (packageName == null) return false;

    try {
      // This is where you'll implement the actual logic to check app usage
      // Options include:
      // 1. Check last launch time
      // 2. Check app's data usage
      // 3. Check if app has been opened in the last week

      // Placeholder implementation - you'll need to replace this
      final platform = MethodChannel('com.arabapps.cleangru/app_usage');

      // Invoke a method to check app usage
      final lastUsedTime = await platform
          .invokeMethod('getAppLastUsedTime', {'packageName': packageName});

      // If no last used time or used more than a week ago, consider it unused
      if (lastUsedTime == null) return true;

      final lastUsed = DateTime.fromMillisecondsSinceEpoch(lastUsedTime);
      final oneWeekAgo = DateTime.now().subtract(Duration(days: 7));

      return lastUsed.isBefore(oneWeekAgo);
    } catch (e) {
      print('Error checking app usage for $packageName: $e');
      return false;
    }
  }

  bool _isSystemApp(installed_package.AppInfo app) {
    final systemPrefixes = [
      'android.',
      'com.android.',
      'com.google.android.',
      'com.google.firebase.',
      'com.sec.',
      'com.htc.',
      'com.sony.',
      'com.motorola.',
      'com.samsung.',
      'com.huawei.',
      'com.xiaomi.',
      'com.oppo.',
      'com.vivo.',
      'com.oneplus.',
    ];

    final systemPatterns = [
      'keyboard',
      'launcher',
      'inputmethod',
      'provider',
      'manager',
      'bluetooth',
      'telephony',
      'system',
      'policy',
    ];

    final packageName = app.packageName?.toLowerCase() ?? '';

    // Check if it starts with known system prefixes
    if (systemPrefixes.any((prefix) => packageName.startsWith(prefix))) {
      return true;
    }

    // Check if it contains system-related patterns
    if (systemPatterns.any((pattern) => packageName.contains(pattern))) {
      return true;
    }

    return false;
  }

  Future<void> _createTestFiles() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        // Create test files
        for (int i = 0; i < 5; i++) {
          final file = File('${directory.path}/testfile_$i.txt');
          // Create files of different sizes: 2MB, 3MB, 4MB, etc.
          final bytes = List<int>.filled(1024 * 1024 * (i + 2), 65);
          await file.writeAsBytes(bytes);
        }
        // Refresh the list
        _scanFiles();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test files created successfully')),
        );
      }
    } catch (e) {
      print('Error creating test files: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating test files')),
      );
    }
  }

  Widget _buildStorageItem(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12)),
            Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  SliverList _buildDuplicateMediaSectionSliver(
    BuildContext context, {
    required List<DuplicateMedia> mediaList,
    required String title,
    required bool isPhotos,
  }) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, sectionIndex) {
          // First item is the section header
          if (sectionIndex == 0) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        for (var media in mediaList) {
                          for (var duplicate in media.duplicates) {
                            duplicate.isSelected = false;
                          }
                        }
                      });
                    },
                    child: Text(
                      'Deselect All',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Subsequent items are media groups
          final currentMedia = mediaList[sectionIndex - 1];
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gridWidth = constraints.maxWidth;
                final gridItemWidth = (gridWidth - 16) / 3;

                return CustomMultiChildLayout(
                  delegate: _DuplicateMediaLayoutDelegate(
                    itemCount: currentMedia.duplicates.length + 1,
                  ),
                  children: [
                    // Large primary image
                    LayoutId(
                      id: _DuplicateMediaLayoutDelegate.primaryImage,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(currentMedia.path),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Best',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Duplicate images
                    ...currentMedia.duplicates.asMap().entries.map((entry) {
                      final duplicateIndex = entry.key;
                      final duplicate = entry.value;
                      return LayoutId(
                        id: duplicateIndex + 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(duplicate.path),
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Checkbox(
                                    value: duplicate.isSelected,
                                    onChanged: (value) {
                                      setState(() {
                                        duplicate.isSelected = value ?? false;
                                      });
                                    },
                                    shape: CircleBorder(),
                                    side: BorderSide.none,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          );
        },
        childCount: mediaList.length + 1, // +1 for the header
      ),
    );
  }

  Widget _buildDuplicateSection(
    BuildContext context, {
    required List<DuplicateMedia> mediaList,
    required String title,
    required bool isPhotos,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 14),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    for (var media in mediaList) {
                      for (var duplicate in media.duplicates) {
                        duplicate.isSelected = false;
                      }
                    }
                  });
                },
                child: Text(
                  'Deselect All',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Large primary image
                  Expanded(
                    flex: 2,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(mediaList[0].path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: constraints.maxWidth * 2 / 3,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Best',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  // Duplicate images grid
                  Expanded(
                    flex: 1,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: mediaList[0].duplicates.length,
                      itemBuilder: (context, index) {
                        final duplicate = mediaList[0].duplicates[index];
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(duplicate.path),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Checkbox(
                                  value: duplicate.isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      duplicate.isSelected = value ?? false;
                                    });
                                  },
                                  shape: CircleBorder(),
                                  side: BorderSide.none,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDuplicateItem(
      BuildContext context, DuplicateMedia currentMedia) {
    // Calculate screen width for responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;

    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with delete button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Duplicates Found (${currentMedia.duplicates.length})",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                // Delete selected button
                if (currentMedia.duplicates.any((dup) => dup.isSelected))
                  TextButton.icon(
                    onPressed: () =>
                        _deleteSelectedDuplicatesForMedia(currentMedia),
                    icon: Icon(Icons.delete, size: 16, color: Colors.red),
                    label: Text(
                      'Delete Selected',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size(0, 0),
                    ),
                  ),
              ],
            ),

            SizedBox(height: 12),

            // Full-width best image
            Container(
              width: double.infinity,
              height: 240, // Taller best image
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Best image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(currentMedia.path),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade300,
                          child:
                              Center(child: Icon(Icons.broken_image, size: 60)),
                        );
                      },
                    ),
                  ),
                  // "Best" badge
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Best',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  // Show size info at the bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      color: Colors.black.withOpacity(0.6),
                      child: Text(
                        '${(currentMedia.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 12),

            // Divider between best and duplicates
            Divider(height: 1, thickness: 1, color: Colors.grey.shade300),

            SizedBox(height: 8),

            // Duplicates label
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Similar Images",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          for (var duplicate in currentMedia.duplicates) {
                            duplicate.isSelected = true;
                          }
                        });
                      },
                      child: Text('Select All', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: Size(0, 0),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          for (var duplicate in currentMedia.duplicates) {
                            duplicate.isSelected = false;
                          }
                        });
                      },
                      child:
                          Text('Deselect All', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: Size(0, 0),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            SizedBox(height: 8),

            // Grid of duplicates - now with larger images
            Container(
              height: 160, // Larger height for duplicates
              child: currentMedia.duplicates.isEmpty
                  ? Center(child: Text('No duplicates found'))
                  : GridView.builder(
                      scrollDirection: Axis.horizontal,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 1, // Single row, horizontal scroll
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: currentMedia.duplicates.length,
                      itemBuilder: (context, duplicateIndex) {
                        final duplicate =
                            currentMedia.duplicates[duplicateIndex];
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            // Duplicate image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(duplicate.path),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey.shade300,
                                    child:
                                        Center(child: Icon(Icons.broken_image)),
                                  );
                                },
                              ),
                            ),
                            // Size info
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 6),
                                color: Colors.black.withOpacity(0.6),
                                child: Text(
                                  '${(duplicate.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            // Checkbox for duplicate images
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: Checkbox(
                                  value: duplicate.isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      duplicate.isSelected = value ?? false;
                                    });
                                  },
                                  shape: CircleBorder(),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAllSelectedMedia(List<DuplicateMedia> mediaList) async {
    try {
      // Count selected originals and duplicates
      int selectedOriginals = 0;
      int selectedDuplicates = 0;

      for (var media in mediaList) {
        if (media.isSelected) {
          selectedOriginals++;
        }
        selectedDuplicates +=
            media.duplicates.where((d) => d.isSelected).length;
      }

      int totalSelected = selectedOriginals + selectedDuplicates;

      if (totalSelected == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No items selected')),
        );
        return;
      }

      // Create appropriate message based on what's selected
      String confirmMessage;
      if (selectedOriginals > 0 && selectedDuplicates > 0) {
        confirmMessage =
            'Are you sure you want to delete $selectedOriginals original images and $selectedDuplicates duplicates?';
      } else if (selectedOriginals > 0) {
        confirmMessage =
            'Are you sure you want to delete $selectedOriginals original images?';
      } else {
        confirmMessage =
            'Are you sure you want to delete $selectedDuplicates duplicates?';
      }

      // Confirm deletion
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Media'),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Deleting media'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Deleting $totalSelected items...'),
            ],
          ),
        ),
      );

      int deletedCount = 0;

      // Delete selected originals and their duplicates
      for (var media in mediaList) {
        // Delete selected duplicates
        for (var duplicate
            in media.duplicates.where((d) => d.isSelected).toList()) {
          final file = File(duplicate.path);
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        }

        // Delete the original if selected
        if (media.isSelected) {
          final file = File(media.path);
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      // Dismiss progress dialog
      Navigator.of(context).pop();

      // Refresh the cache to update the UI
      _resetDuplicatesCache();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully deleted $deletedCount items'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss progress dialog if showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error deleting media: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting media: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Widget _buildDuplicateMediaSection(
    BuildContext context, {
    required List<DuplicateMedia> mediaList,
    required String title,
    required bool isPhotos,
  }) {
    final isEnglish =
        Provider.of<LanguageProvider>(context).currentLocale.languageCode ==
            'en';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section title - keep as is, we'll translate it where it's used
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),

              // Section description
              Text(
                isEnglish
                    ? 'Best images are protected. You can only delete duplicates.'
                    : 'الصور الأفضل محمية. يمكنك فقط حذف النسخ المكررة.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),

        // Container with height constraint for the scrollable list
        Container(
          height: MediaQuery.of(context).size.height *
              0.55, // Reduced height to accommodate selection count
          child: ListView.builder(
            shrinkWrap: false,
            physics: AlwaysScrollableScrollPhysics(),
            itemCount: mediaList.length,
            itemBuilder: (context, index) {
              return _buildBestImageProtectedItem(context, mediaList[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBestImageProtectedItem(
      BuildContext context, DuplicateMedia currentMedia) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Layout with best image on the left and duplicates on the right
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Best image (larger) - NO CHECKBOX (Protected)
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Image.file(
                          File(currentMedia.path),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 180,
                              color: Colors.grey.shade300,
                              child: Center(
                                  child: Icon(Icons.broken_image, size: 40)),
                            );
                          },
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Best',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(width: 8),

                // Duplicates (smaller, in a column) - WITH CHECKBOXES
                Expanded(
                  flex: 2,
                  child: Column(
                    children: currentMedia.duplicates.map((duplicate) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(duplicate.path),
                                height: 85,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 85,
                                    color: Colors.grey.shade300,
                                    child: Center(
                                        child:
                                            Icon(Icons.broken_image, size: 24)),
                                  );
                                },
                              ),
                            ),
                            // Checkbox only on duplicate images
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: Checkbox(
                                  value: duplicate.isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      duplicate.isSelected = value ?? false;
                                    });
                                  },
                                  shape: CircleBorder(),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            // REMOVED: Size info and duplicate count information that was below the best image
            // The following section has been removed:
            /*
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.shield, size: 16, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'Best: ${_formatFileSize(currentMedia.size)} (Protected)',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Number of duplicates and combined size
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '${currentMedia.duplicates.length} duplicates - ${_formatFileSize(currentMedia.duplicates.fold(0, (sum, item) => sum + item.size))} total',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          */
          ],
        ),
      ),
    );
  }



  Future<void> _deleteSelectedDuplicatesForMedia(DuplicateMedia media) async {
    final isEnglish = Provider.of<LanguageProvider>(context, listen: false)
            .currentLocale
            .languageCode ==
        'en';

    try {
      // Count selected duplicates (only from the duplicates array, not the original)
      final selectedDuplicates =
          media.duplicates.where((d) => d.isSelected).toList();
      final selectedCount = selectedDuplicates.length;

      if (selectedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(isEnglish
                  ? 'No duplicates selected'
                  : 'لم يتم تحديد أي نسخ متكررة')),
        );
        return;
      }

      // Confirm deletion
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(isEnglish
              ? 'Delete Selected Duplicates'
              : 'حذف النسخ المكررة المحددة'),
          content: Text(isEnglish
              ? 'Are you sure you want to delete $selectedCount selected duplicates?'
              : 'هل أنت متأكد من رغبتك في حذف $selectedCount من النسخ المكررة المحددة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(isEnglish ? 'Cancel' : 'إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isEnglish ? 'Delete' : 'حذف',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(
              isEnglish ? 'Deleting duplicates' : 'جاري حذف النسخ المكررة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(isEnglish
                  ? 'Deleting $selectedCount duplicates...'
                  : 'جاري حذف $selectedCount من النسخ المكررة...'),
            ],
          ),
        ),
      );

      int deletedCount = 0;
      List<String> deletedPaths = [];

      // Delete ONLY the selected duplicates from the device storage
      for (var duplicate in selectedDuplicates) {
        try {
          final file = File(duplicate.path);
          if (await file.exists()) {
            // Step 1: Get the file path
            final String filePath = duplicate.path;

            // Step 2: Delete the actual file
            await file.delete();
            deletedCount++;
            deletedPaths.add(filePath);

            // Step 3: IMPORTANT - Notify Android's MediaStore about the deletion
            if (Platform.isAndroid) {
              try {
                // Use the static media channel
                const platform = MethodChannel('com.example.clean_guru/media');

                // First try the direct MediaStore notification
                await platform.invokeMethod(
                    'notifyMediaStoreFileDeleted', {'filePath': filePath});

                // Also try the media scanner approach as a backup
                await platform.invokeMethod('scanFile', {'path': filePath});

                print(
                    'Successfully notified MediaStore about deletion: $filePath');
              } catch (e) {
                print('Error notifying MediaStore: $e');
              }
            }
          }
        } catch (e) {
          print('Error deleting file ${duplicate.path}: $e');
        }
      }

      // Update the UI by removing the deleted duplicates from the media's duplicate list
      setState(() {
        media.duplicates.removeWhere((d) => deletedPaths.contains(d.path));

        // Mark this best image to be preserved in the list
        _keepInListImages.add(media.path);

        // Make sure to save this preference
        _savePreservedImages();
      });

      // Dismiss progress dialog
      Navigator.of(context).pop();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEnglish
              ? 'Successfully deleted $deletedCount duplicates'
              : 'تم حذف $deletedCount من النسخ المكررة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss progress dialog if showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error deleting duplicates: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEnglish
              ? 'Error deleting duplicates: $e'
              : 'خطأ في حذف النسخ المكررة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Set<String> _keepInListImages = {};

  Widget _buildSimplifiedDuplicateItem(
      BuildContext context, DuplicateMedia currentMedia) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Layout with best image on the left and duplicates on the right
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Best image (larger)
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Image.file(
                          File(currentMedia.path),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 180,
                              color: Colors.grey.shade300,
                              child: Center(
                                  child: Icon(Icons.broken_image, size: 40)),
                            );
                          },
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Best',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(width: 8),

                // Duplicates (smaller, in a column)
                Expanded(
                  flex: 2,
                  child: Column(
                    children: currentMedia.duplicates.map((duplicate) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(duplicate.path),
                                height: 85,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 85,
                                    color: Colors.grey.shade300,
                                    child: Center(
                                        child:
                                            Icon(Icons.broken_image, size: 24)),
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: Checkbox(
                                  value: duplicate.isSelected,
                                  onChanged: (value) {
                                    setState(() {
                                      duplicate.isSelected = value ?? false;
                                    });
                                  },
                                  shape: CircleBorder(),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            // Size info (optional)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Original: ${_formatFileSize(currentMedia.size)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAllSelectedDuplicates(
      List<DuplicateMedia> mediaList) async {
    try {
      // Count all selected duplicates
      int totalSelectedCount = 0;
      for (var media in mediaList) {
        totalSelectedCount +=
            media.duplicates.where((d) => d.isSelected).length;
      }

      if (totalSelectedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No duplicates selected')),
        );
        return;
      }

      // Confirm deletion
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Duplicates'),
          content: Text(
              'Are you sure you want to delete $totalSelectedCount selected duplicates?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Deleting duplicates'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Deleting $totalSelectedCount duplicates...'),
            ],
          ),
        ),
      );

      int deletedCount = 0;

      // Delete selected duplicates from each media item
      for (var media in mediaList) {
        final selectedDuplicates =
            media.duplicates.where((d) => d.isSelected).toList();

        for (var duplicate in selectedDuplicates) {
          final file = File(duplicate.path);
          if (await file.exists()) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      // Dismiss progress dialog
      Navigator.of(context).pop();

      // Refresh the cache to update the UI
      _resetDuplicatesCache();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully deleted $deletedCount duplicates'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss progress dialog if showing
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error deleting duplicates: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting duplicates: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, List<DuplicateMedia>>> _getScannedDuplicates() async {
    if (_cachedDuplicatesResult != null) {
      return _cachedDuplicatesResult!;
    }

    if (_isDuplicateScanning) {
      // If a scan is already in progress, wait for a bit and check again
      await Future.delayed(Duration(milliseconds: 500));
      return _getScannedDuplicates();
    }

    _isDuplicateScanning = true;
    try {
      final result = await _scanGalleryForDuplicates();
      _cachedDuplicatesResult = result;
      return result;
    } catch (e) {
      print('Error in _getScannedDuplicates: $e');
      _isDuplicateScanning = false;
      // Rethrow the error so it can be caught by the FutureBuilder
      rethrow;
    } finally {
      _isDuplicateScanning = false;
    }
  }

  /* void _resetDuplicatesCache() {
    setState(() {
      _duplicatesFuture = null;
      _cachedDuplicatesResult = null;
    });
  }*/

  void _resetDuplicatesCache() {
    // Check if we have existing data first
    final existingData = _cachedDuplicatesResult;

    if (existingData != null) {
      // Create a map of paths that should be preserved (best images)
      final bestImagePaths = <String>{};

      for (var category in ['photos', 'videos']) {
        for (var media in existingData[category] ?? []) {
          // Add the path of the best image to our set
          bestImagePaths.add(media.path);
        }
      }

      // Store this for use when refreshing
      setState(() {
        _preservedBestImages = bestImagePaths;
        _duplicatesFuture = null;
        _cachedDuplicatesResult = null;
      });
    } else {
      // Simple reset if no existing data
      setState(() {
        _duplicatesFuture = null;
        _cachedDuplicatesResult = null;
      });
    }
  }

  Set<String> _preservedBestImages = {};


  Future<Map<String, List<DuplicateMedia>>> _scanGalleryForDuplicates() async {
    try {
      setState(() {
        _isDuplicateScanning = true;
      });

      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        throw Exception('Storage permissions required');
      }

      // OPTIMIZATION 1: Collect all media files first
      final List<DuplicateMedia> allMediaFiles = [];
      final directoriesToCheck = [
        '/storage/emulated/0/DCIM/Camera', // Prioritize camera folder
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Download',
      ];

      // OPTIMIZATION 2: Process far fewer files - users care most about recent photos
      int maxFilesToProcess = 50; // Drastically reduced
      int processedFiles = 0;

      // Track all unique file paths to avoid duplicates from the beginning
      final Set<String> uniqueFilePaths = {};

      // OPTIMIZATION 3: Fast scanning without waiting for full directory lists
      for (String dirPath in directoriesToCheck) {
        if (processedFiles >= maxFilesToProcess) break;

        try {
          final directory = Directory(dirPath);
          if (await directory.exists()) {
            // Fast scan with limit
            final entities = directory.listSync(
                recursive: dirPath.contains('Camera') ? false : true);

            // OPTIMIZATION 4: Sort by modified time to prioritize recent files
            if (dirPath.contains('Camera')) {
              final imageFiles = entities
                  .whereType<File>()
                  .where((file) => isImageFile(file.path))
                  .toList();

              // Sort by modification time (newest first)
              imageFiles.sort((a, b) {
                final statA = a.statSync();
                final statB = b.statSync();
                return statB.modified.compareTo(statA.modified);
              });

              // Take only the most recent files
              for (var file in imageFiles.take(maxFilesToProcess)) {
                // Skip if we've already processed this file path
                if (uniqueFilePaths.contains(file.path)) continue;

                uniqueFilePaths.add(file.path);
                final stat = file.statSync();
                allMediaFiles.add(DuplicateMedia(
                  path: file.path,
                  thumbnailPath: file.path,
                  timestamp: stat.modified,
                  size: stat.size,
                  duplicates: const [],
                ));
                processedFiles++;
              }
            } else {
              // For non-camera folders, just take a few samples
              for (var entity in entities) {
                if (processedFiles >= maxFilesToProcess) break;

                if (entity is File && isImageFile(entity.path)) {
                  // Skip if we've already processed this file path
                  if (uniqueFilePaths.contains(entity.path)) continue;

                  uniqueFilePaths.add(entity.path);
                  final stat = entity.statSync();
                  allMediaFiles.add(DuplicateMedia(
                    path: entity.path,
                    thumbnailPath: entity.path,
                    timestamp: stat.modified,
                    size: stat.size,
                    duplicates: const [],
                  ));
                  processedFiles++;
                }
              }
            }
          }
        } catch (e) {
          print('Error accessing directory $dirPath: $e');
        }
      }

      // Early return if no files
      if (allMediaFiles.isEmpty) {
        setState(() {
          _isDuplicateScanning = false;
        });
        return {'photos': [], 'videos': []};
      }

      // CRITICAL FIX: Process all camera photos as a single batch first
      // This ensures recent camera photos are grouped together correctly
      final cameraPhotos = allMediaFiles
          .where((media) =>
              media.path.contains('/DCIM/Camera/') ||
              media.path.contains('/Pictures/Camera/'))
          .toList();

      final otherPhotos = allMediaFiles
          .where((media) => !(media.path.contains('/DCIM/Camera/') ||
              media.path.contains('/Pictures/Camera/')))
          .toList();

      // Track processed file paths to prevent any image from appearing twice
      final Set<String> processedFilePaths = {};
      final List<DuplicateMedia> duplicateGroups = [];

      // Process camera photos first if there are any
      if (cameraPhotos.length >= 2) {
        _processCameraPhotosForDuplicates(
            cameraPhotos, duplicateGroups, processedFilePaths);
      }

      // Only process remaining photos if they weren't already included in camera groups
      if (otherPhotos.isNotEmpty) {
        _processRemainingPhotosForDuplicates(
            otherPhotos, duplicateGroups, processedFilePaths);
      }

      setState(() {
        _isDuplicateScanning = false;
      });

      return {
        'photos': duplicateGroups,
        'videos': [], // Not processing videos in fast mode
      };
    } catch (e) {
      setState(() {
        _isDuplicateScanning = false;
      });
      print('Error in fast scan: $e');
      rethrow;
    }
  }

  void _processCameraPhotosForDuplicates(List<DuplicateMedia> cameraPhotos,
      List<DuplicateMedia> results, Set<String> processedFilePaths) {
    // Skip if too few photos or already processed
    if (cameraPhotos.length < 2) return;

    // Group by time proximity for camera photos
    // Use a shorter time window (30 seconds) for camera burst shots
    final Map<String, List<DuplicateMedia>> timeGroups = {};

    for (var media in cameraPhotos) {
      if (processedFilePaths.contains(media.path)) continue;

      bool added = false;
      for (var timeKey in timeGroups.keys) {
        final referencePhoto = timeGroups[timeKey]!.first;
        // If taken within 30 seconds, consider as same burst
        if (media.timestamp
                .difference(referencePhoto.timestamp)
                .inSeconds
                .abs() <=
            30) {
          timeGroups[timeKey]!.add(media);
          added = true;
          break;
        }
      }

      if (!added) {
        timeGroups[media.path] = [media];
      }
    }

    // For each time group, check filename similarities
    for (var photoGroup in timeGroups.values) {
      if (photoGroup.length < 2) continue;

      // See if filenames are similar (often camera photos have sequence numbers)
      Map<String, List<DuplicateMedia>> namePatternGroups = {};

      for (var photo in photoGroup) {
        final filename = path.basenameWithoutExtension(photo.path);
        // Extract base name pattern by removing digits
        String basePattern = filename.replaceAll(RegExp(r'\d+'), '');

        if (basePattern.isNotEmpty) {
          namePatternGroups.putIfAbsent(basePattern, () => []).add(photo);
        } else {
          // If no pattern, use the timestamp as key
          namePatternGroups
              .putIfAbsent(
                  'time_${photo.timestamp.millisecondsSinceEpoch}', () => [])
              .add(photo);
        }
      }

      // Create duplicate groups from the name pattern groups
      for (var patternGroup in namePatternGroups.values) {
        if (patternGroup.length < 2) continue;

        // Check if any image in this group is a preserved best image
        var hasBestImage = false;
        DuplicateMedia? bestMedia;

        for (var media in patternGroup) {
          if (_preservedBestImages.contains(media.path)) {
            hasBestImage = true;
            bestMedia = media;
            break;
          }
        }

        if (hasBestImage && bestMedia != null) {
          // Use the preserved best image as the original
          final duplicates =
              patternGroup.where((m) => m.path != bestMedia!.path).toList();

          // Mark all as processed
          for (var photo in patternGroup) {
            processedFilePaths.add(photo.path);
          }

          results.add(DuplicateMedia(
            path: bestMedia.path,
            thumbnailPath: bestMedia.thumbnailPath,
            timestamp: bestMedia.timestamp,
            size: bestMedia.size,
            isSelected: false,
            duplicates: duplicates,
          ));
        } else {
          // No preserved best image, sort by timestamp (newest first for camera photos)
          patternGroup.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Use newest as "best" for camera photos (usually last shot is better)
          final original = patternGroup.first;
          final duplicates = patternGroup.sublist(1);

          // Mark all as processed
          for (var photo in patternGroup) {
            processedFilePaths.add(photo.path);
          }

          results.add(DuplicateMedia(
            path: original.path,
            thumbnailPath: original.thumbnailPath,
            timestamp: original.timestamp,
            size: original.size,
            isSelected: false,
            duplicates: duplicates,
          ));
        }
      }
    }
  }

  void _processRemainingPhotosForDuplicates(List<DuplicateMedia> photos,
      List<DuplicateMedia> results, Set<String> processedFilePaths) {
    // Group by exact file size first
    final Map<int, List<DuplicateMedia>> sizeGroups = {};
    for (var media in photos) {
      if (!processedFilePaths.contains(media.path)) {
        sizeGroups.putIfAbsent(media.size, () => []).add(media);
      }
    }

    // Only keep groups with potential duplicates
    sizeGroups.removeWhere((_, group) => group.length < 2);

    // For each size group, process by filename similarity
    for (var sizeGroup in sizeGroups.values) {
      // Skip if already processed
      sizeGroup = sizeGroup
          .where((media) => !processedFilePaths.contains(media.path))
          .toList();
      if (sizeGroup.length < 2) continue;

      // Group by filename pattern
      final Map<String, List<DuplicateMedia>> nameGroups = {};

      for (var media in sizeGroup) {
        final filename =
            path.basenameWithoutExtension(media.path).toLowerCase();
        // Simplified filename normalization
        final normalized = filename.replaceAll(RegExp(r'[^a-z]'), '');

        if (normalized.isNotEmpty) {
          nameGroups.putIfAbsent(normalized, () => []).add(media);
        }
      }

      // Process each name group
      for (var nameGroup in nameGroups.values) {
        if (nameGroup.length < 2) continue;

        // Filter out already processed files
        nameGroup = nameGroup
            .where((media) => !processedFilePaths.contains(media.path))
            .toList();
        if (nameGroup.length < 2) continue;

        // Group by time proximity
        final Map<String, List<DuplicateMedia>> timeGroups = {};

        for (var media in nameGroup) {
          if (processedFilePaths.contains(media.path)) continue;

          bool added = false;
          for (var timeKey in timeGroups.keys) {
            final refMedia = timeGroups[timeKey]!.first;
            // If within 5 minutes, consider same burst
            if (media.timestamp
                    .difference(refMedia.timestamp)
                    .inMinutes
                    .abs() <=
                5) {
              timeGroups[timeKey]!.add(media);
              added = true;
              break;
            }
          }

          if (!added) {
            timeGroups[media.path] = [media];
          }
        }

        // Create duplicate groups
        for (var timeGroup in timeGroups.values) {
          if (timeGroup.length < 2) continue;

          // Check if any image in this group is a preserved best image
          var hasBestImage = false;
          DuplicateMedia? bestMedia;

          for (var media in timeGroup) {
            if (_preservedBestImages.contains(media.path)) {
              hasBestImage = true;
              bestMedia = media;
              break;
            }
          }

          if (hasBestImage && bestMedia != null) {
            // Use the preserved best image as the original
            final duplicates =
                timeGroup.where((m) => m.path != bestMedia!.path).toList();

            // Mark all as processed
            for (var media in timeGroup) {
              processedFilePaths.add(media.path);
            }

            results.add(DuplicateMedia(
              path: bestMedia.path,
              thumbnailPath: bestMedia.thumbnailPath,
              timestamp: bestMedia.timestamp,
              size: bestMedia.size,
              isSelected: false,
              duplicates: duplicates,
            ));
          } else {
            // For non-camera photos, older is usually the original
            timeGroup.sort((a, b) => a.timestamp.compareTo(b.timestamp));

            final original = timeGroup.first;
            final duplicates = timeGroup.sublist(1);

            // Mark all as processed
            for (var media in timeGroup) {
              processedFilePaths.add(media.path);
            }

            results.add(DuplicateMedia(
              path: original.path,
              thumbnailPath: original.thumbnailPath,
              timestamp: original.timestamp,
              size: original.size,
              isSelected: false,
              duplicates: duplicates,
            ));
          }
        }
      }
    }
  }

// Depth-first search to find connected components
  void _dfs(String node, Map<String, Set<String>> graph, Set<String> visited,
      Set<String> component) {
    visited.add(node);
    component.add(node);

    for (var neighbor in graph[node] ?? {}) {
      if (!visited.contains(neighbor)) {
        _dfs(neighbor, graph, visited, component);
      }
    }
  }

  double _compareHashesWithEarlyExit(List<bool> hash1, List<bool> hash2) {
    if (hash1.length != hash2.length) return 0.0;

    int differences = 0;
    final maxDifferences =
        (hash1.length * 0.2).ceil(); // Max differences for 80% similarity

    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) {
        differences++;

        // Early exit if we exceed threshold
        if (differences > maxDifferences) {
          return 0.0;
        }
      }
    }

    return ((hash1.length - differences) / hash1.length) * 100;
  }

  Future<List<bool>?> _calculateOptimizedHash(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return null;

      // Use smaller hash size (8x8 instead of 16x16) for much faster processing
      const hashSize = 8;

      // Use nearest neighbor for faster resizing
      final resized = img.copyResize(image,
          width: hashSize,
          height: hashSize,
          interpolation: img.Interpolation.nearest);

      final grayscale = img.grayscale(resized);
      final pixels = grayscale.data;

      if (pixels == null) return null;

      // Faster grayscale calculation
      int sum = 0;
      for (var pixel in pixels) {
        sum += ((pixel.r + pixel.g + pixel.b) ~/ 3);
      }

      final avg = (sum / pixels.length).round();

      // Generate hash
      return pixels.map((pixel) {
        int value = ((pixel.r + pixel.g + pixel.b) ~/ 3);
        return value > avg;
      }).toList();
    } catch (e) {
      print('Error calculating hash for $imagePath: $e');
      return null;
    }
  }

  Future<void> _processGroupForDuplicates(List<DuplicateMedia> group,
      List<DuplicateMedia> results, Map<String, List<bool>> hashCache) async {
    // Calculate hashes for all images in the group
    for (var media in group) {
      if (!hashCache.containsKey(media.path)) {
        try {
          final hash = await _calculateOptimizedHash(media.path);
          if (hash != null) {
            hashCache[media.path] = hash;
          }
        } catch (e) {
          print('Error calculating hash for ${media.path}: $e');
        }
      }
    }

    // Build a similarity graph
    Map<String, Set<String>> similarityGraph = {};

    // Initialize graph with each file
    for (var media in group) {
      if (hashCache.containsKey(media.path)) {
        similarityGraph[media.path] = {};
      }
    }

    // Find similar images with optimized comparison
    final similarityThreshold = 80.0;

    for (int i = 0; i < group.length; i++) {
      final mediaA = group[i];
      final hashA = hashCache[mediaA.path];

      if (hashA == null) continue;

      for (int j = i + 1; j < group.length; j++) {
        final mediaB = group[j];
        final hashB = hashCache[mediaB.path];

        if (hashB == null) continue;

        // Use optimized hash comparison with early termination
        final similarity = _compareHashesWithEarlyExit(hashA, hashB);

        if (similarity >= similarityThreshold) {
          similarityGraph[mediaA.path]?.add(mediaB.path);
          similarityGraph[mediaB.path]?.add(mediaA.path);
        }
      }
    }

    // Find connected components (groups of similar images)
    Set<String> visited = {};
    List<Set<String>> components = [];

    for (var node in similarityGraph.keys) {
      if (!visited.contains(node)) {
        Set<String> component = {};
        _dfs(node, similarityGraph, visited, component);

        if (component.length > 1) {
          components.add(component);
        }
      }
    }

    // Create DuplicateMedia objects for each component
    for (var component in components) {
      List<DuplicateMedia> mediaInComponent =
          group.where((media) => component.contains(media.path)).toList();

      // Sort by timestamp (oldest first)
      mediaInComponent.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Use the oldest file as the original
      final original = mediaInComponent.first;
      final duplicates = mediaInComponent.sublist(1);

      // Create DuplicateMedia with duplicates
      results.add(DuplicateMedia(
        path: original.path,
        thumbnailPath: original.thumbnailPath,
        timestamp: original.timestamp,
        size: original.size,
        isSelected: false,
        duplicates: duplicates,
      ));
    }
  }

  Future<List<bool>?> _calculatePerceptualHash(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) return null;

      // Hash size (number of bits in each dimension)
      const hashSize = 16;

      // Resize to small square for hash calculation
      final resized = img.copyResize(image, width: hashSize, height: hashSize);
      final grayscale = img.grayscale(resized);
      final pixels = grayscale.data;

      if (pixels == null) return null;

      // Calculate average pixel value using RGB values
      int sum = 0;
      for (var pixel in pixels) {
        // Calculate grayscale value using luminance formula
        int grayscaleValue =
            ((pixel.r * 0.299) + (pixel.g * 0.587) + (pixel.b * 0.114)).round();
        sum += grayscaleValue;
      }

      final avg = (sum / (hashSize * hashSize)).round();

      // Generate hash based on whether pixel is above or below average
      return pixels.map((pixel) {
        int grayscaleValue =
            ((pixel.r * 0.299) + (pixel.g * 0.587) + (pixel.b * 0.114)).round();
        return grayscaleValue > avg;
      }).toList();
    } catch (e) {
      print('Error calculating perceptual hash for $imagePath: $e');
      return null;
    }
  }

  double _compareHashes(List<bool> hash1, List<bool> hash2) {
    if (hash1.length != hash2.length) return 0.0;

    int similarities = 0;
    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] == hash2[i]) similarities++;
    }

    return (similarities / hash1.length) * 100;
  }

  String _generateGroupHash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  Widget _buildStorageInfo(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Future<void> createTestDuplicates() async {
    try {
      // Request permissions first
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission required');
      }

      // Create test directories
      final dcimDir = Directory('/storage/emulated/0/DCIM/TestDuplicates');
      final downloadDir =
          Directory('/storage/emulated/0/Download/TestDuplicates');

      await dcimDir.create(recursive: true);
      await downloadDir.create(recursive: true);

      // Create sample images with duplicates
      for (int i = 1; i <= 3; i++) {
        final image = img.Image(width: 800, height: 600);

        // Fill with different colors for different images
        img.fill(image, color: img.ColorRgb8(i * 50, i * 80, i * 100));

        // Add some text
        img.drawString(image, 'Test Image $i',
            font: img.arial48,
            x: 50,
            y: 50,
            color: img.ColorRgb8(255, 255, 255));

        final bytes = img.encodeJpg(image);

        // Save original and duplicates
        await File('${dcimDir.path}/image_$i.jpg').writeAsBytes(bytes);
        await File('${downloadDir.path}/image_${i}_copy1.jpg')
            .writeAsBytes(bytes);
        await File('${downloadDir.path}/image_${i}_copy2.jpg')
            .writeAsBytes(bytes);
      }

      // After creating files, trigger a scan
      _scanFiles();
      _resetDuplicatesCache();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Test files created successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating test files: $e')),
      );
    }
  }

  Widget _buildMediaThumbnail(
    DuplicateMedia media,
    double width,
    double height, {
    bool isOriginal = false,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            onTap: () => _previewMedia(media),
            child: Stack(
              children: [
                Image.file(
                  File(media.thumbnailPath),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.black54,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(media.size / 1024 / 1024).toStringAsFixed(1)} MB',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        Text(
                          DateFormat('MMM d, yyyy').format(media.timestamp),
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isOriginal)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Checkbox(
                value: media.isSelected,
                onChanged: (value) => _toggleMediaSelection(media),
                shape: CircleBorder(),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> checkForCameraDuplicates() async {
    try {
      // Get camera directory
      final cameraDir = Directory('/storage/emulated/0/DCIM/Camera');
      if (!await cameraDir.exists()) {
        print('Camera directory does not exist');
        return;
      }

      // Set loading state
      setState(() {
        _isDuplicateScanning = true;
      });

      // Refresh the duplicate scan to include the new photos
      _cachedDuplicatesResult = null;
      _duplicatesFuture = _getScannedDuplicates();

      // Wait for the scan to complete
      await _duplicatesFuture;

      // Reset loading state
      setState(() {
        _isDuplicateScanning = false;
      });

      // Switch to the duplicates tab
      _tabController.animateTo(0); // Assuming duplicates tab is at index 0
    } catch (e) {
      print('Error checking for camera duplicates: $e');
    }
  }

  void _toggleAppSelection(AppInfo app) {
    setState(() {
      app.isSelected = !app.isSelected;
    });
  }

  String _formatAppSize(int bytes) {
    if (bytes < 1024 * 1024) {
      // Less than 1 MB
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      // Less than 1 GB
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

// Updated method to delete only selected duplicates

  void _toggleAllApps(bool selected) {
    setState(() {
      for (var app in installedApps) {
        app.isSelected = selected;
      }
    });
  }

  Widget _buildVideoList() {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (context, index) => _buildVideoListItem(),
    );
  }

  Widget _buildVideoListItem() {
    return ListTile(
      leading: Image.asset('assets/video_thumbnail.png',
          width: 60, height: 60, fit: BoxFit.cover),
      title: Text('Video Name'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Taken 12/03/2023'),
          Text('Duration 03:40'),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('500 MB'),
          Checkbox(
            value: true,
            onChanged: (value) {},
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          ),
        ],
      ),
    );
  }
}

bool isVideoFile(String filePath) {
  final ext = path.extension(filePath).toLowerCase();
  return ['.mp4', '.mov', '.avi', '.mkv', '.wmv'].contains(ext);
}

String _formatSize(int bytes) {
  if (bytes < 1024 * 1024) {
    // Less than 1 MB
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    // Less than 1 GB
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

Future<List<String>> getMediaDirectories() async {
  final dirs = await getExternalStorageDirectories();
  return dirs?.map((dir) => dir.path).toList() ?? [];
}

class _DuplicateMediaLayoutDelegate extends MultiChildLayoutDelegate {
  final int itemCount;
  static const primaryImage = 'primaryImage';

  _DuplicateMediaLayoutDelegate({required this.itemCount});

  @override
  void performLayout(Size size) {
    final gridItemWidth = (size.width - 16) / 3;

    // Layout primary image (spanning 2 grid cells)
    layoutChild(
        primaryImage,
        BoxConstraints.tightFor(
            width: gridItemWidth * 2 + 8, height: gridItemWidth * 2 + 8));
    positionChild(primaryImage, Offset.zero);

    // Layout duplicate images
    for (int i = 1; i < itemCount; i++) {
      final childSize = layoutChild(i,
          BoxConstraints.tightFor(width: gridItemWidth, height: gridItemWidth));

      // Calculate position for each duplicate image
      final row = (i - 1) ~/ 2;
      final col = (i - 1) % 2;

      positionChild(
          i,
          Offset(gridItemWidth * 2 + 8 + col * (gridItemWidth + 8),
              row * (gridItemWidth + 8)));
    }
  }

  @override
  bool shouldRelayout(covariant MultiChildLayoutDelegate oldDelegate) => false;
}
