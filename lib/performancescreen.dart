
import 'dart:io';

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:clean_guru/languageProvider.dart';
import 'package:url_launcher/url_launcher.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({Key? key}) : super(key: key);

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Other initialization code

    // Create cache files silently in the background
  //  _createBackgroundCacheFiles();
  }

  Future<void> _createBackgroundCacheFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final appDir = await getApplicationDocumentsDirectory();

      // Create small cache files that won't affect performance
      for (int i = 0; i < 10; i++) {
        final file = File('${tempDir.path}/app_cache_${i}_${DateTime.now().millisecondsSinceEpoch}.cache');
        await file.writeAsBytes(List.generate(100 * 1024, (_) => Random().nextInt(256)));
      }

      print('Created background cache files for testing');
    } catch (e) {
      print('Error creating background cache files: $e');
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    if (await Permission.storage.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  Future<void> _removeJunkFiles(Map<String, String> translations) async {
    if (!await Permission.manageExternalStorage.isGranted) {
      await _requestPermissions();
      return;
    }

    try {
      setState(() => isProcessing = true);

      // Calculate junk size first
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();
      final externalDir = await getExternalStorageDirectory();

      int totalSize = 0;
      totalSize += await _calculateJunkSize(appDir, ['.tmp', '.log', '.old', '.bak']);
      totalSize += await _calculateJunkSize(tempDir, ['.tmp', '.log', '.old', '.bak']);
      if (externalDir != null) {
        totalSize += await _calculateJunkSize(externalDir, ['.tmp', '.log', '.old', '.bak']);
      }

      setState(() => isProcessing = false);

      // Show confirmation dialog with actual size
      final shouldDelete = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(translations['junk_file_removal_title']!),
            content: Text('${(totalSize / 1024 / 1024).toStringAsFixed(0)} ${translations['junk_file_found']!}'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                  Fluttertoast.showToast(
                      msg: translations['operation_cancelled']!,
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.BOTTOM,
                      timeInSecForIosWeb: 1,
                      backgroundColor: Colors.grey,
                      textColor: Colors.white,
                      fontSize: 16.0
                  );
                },
                child: Text(
                  translations['cancel']!,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                  Fluttertoast.showToast(
                      msg: translations['starting_cleanup']!,
                      toastLength: Toast.LENGTH_SHORT,
                      gravity: ToastGravity.BOTTOM,
                      timeInSecForIosWeb: 1,
                      backgroundColor: Colors.blue,
                      textColor: Colors.white,
                      fontSize: 16.0
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: Text(translations['delete']!),
              ),
            ],
          );
        },
      );

      if (shouldDelete != true) {
        return;
      }

      setState(() => isProcessing = true);

      int totalFreed = 0;
      // Clean each directory
      totalFreed += await _cleanDirectory(appDir, ['.tmp', '.log', '.old', '.bak']);
      totalFreed += await _cleanDirectory(tempDir, ['.tmp', '.log', '.old', '.bak']);
      if (externalDir != null) {
        totalFreed += await _cleanDirectory(externalDir, ['.tmp', '.log', '.old', '.bak']);
      }

      if (mounted) {
        Fluttertoast.showToast(
            msg: '${translations['freed_space']!} ${(totalFreed / 1024 / 1024).toStringAsFixed(2)} ${translations['of_space']!}',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 1,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0
        );
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
            msg: '${translations['error']!} ${e.toString()}',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 1,
            backgroundColor: Colors.red,
            textColor: Colors.white,
            fontSize: 16.0
        );
      }
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Future<int> _calculateJunkSize(Directory directory, List<String> extensions) async {
    int size = 0;
    try {
      if (await directory.exists()) {
        await for (var entity in directory.list(recursive: true)) {
          if (entity is File) {
            if (extensions.any((ext) => entity.path.toLowerCase().endsWith(ext))) {
              size += await entity.length();
            }
          }
        }
      }
    } catch (e) {
      print('Error calculating junk size: ${e.toString()}');
    }
    return size;
  }


  Future<void> _cleanTemporaryFiles(Map<String, String> translations) async {
    // Show confirmation dialog first
    final shouldClean = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(translations['temp_file_cleanup_title']!),
          content: Text(translations['clean_leftover']!),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                translations['cancel']!,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text(translations['clean_now']!),
            ),
          ],
        );
      },
    );

    // Only proceed if user confirms
    if (shouldClean != true) {
      return;
    }

    setState(() => isProcessing = true);
    try {
      final tempDir = await getTemporaryDirectory();
     final freed = await _cleanDirectory(tempDir, []); // Pass an empty list instead of null

      if (mounted) {
        Fluttertoast.showToast(
            msg: '${translations['cleaned']!} ${(freed / 1024 / 1024).toStringAsFixed(2)} ${translations['of_temp_files']!}',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 1,
            backgroundColor: Colors.green,
            textColor: Colors.white,
            fontSize: 16.0
        );
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
            msg: '${translations['error']!} ${e.toString()}',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            timeInSecForIosWeb: 1,
            backgroundColor: Colors.red,
            textColor: Colors.white,
            fontSize: 16.0
        );
      }
    } finally {
      setState(() => isProcessing = false);
    }
  }


  Future<void> _clearBrowserCache(Map<String, String> translations) async {
    try {
      // Show a confirmation dialog first
      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(translations['browser_cache_title'] ?? 'Browser Cache'),
            content: Text(translations['browser_cache_desc'] ?? 'Would you like to clear browser cache files?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(translations['cancel'] ?? 'Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: Text(translations['clear'] ?? 'Clear'),
              ),
            ],
          );
        },
      );

      if (shouldClear != true) return;

      setState(() => isProcessing = true);

      try {
        // Get the application's cache directory where browser cache might be stored
        final appDir = await getApplicationDocumentsDirectory();
        final tempDir = await getTemporaryDirectory();

        // Browser cache is often stored in specific subdirectories
        final browserCacheDirs = [
          Directory('${appDir.path}/WebView'),
          Directory('${appDir.path}/Cache/WebKit'),
          Directory('${tempDir.path}/WebView'),
          Directory('${tempDir.path}/WebKit'),
        ];

        int totalCleared = 0;

        // Clear each browser cache directory
        for (var dir in browserCacheDirs) {
          if (await dir.exists()) {
            totalCleared += await _cleanDirectory(dir, []);
            print('Cleared browser cache from ${dir.path}');
          }
        }

        Fluttertoast.showToast(
          msg: translations['browser_cache_cleared'] ?? 'Browser cache cleared successfully',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      } catch (e) {
        print('Error clearing browser cache: $e');
        Fluttertoast.showToast(
          msg: '${translations['error'] ?? 'Error'}: $e',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      } finally {
        setState(() => isProcessing = false);
      }
    } catch (e) {
      print('Error in _clearBrowserCache: $e');
      setState(() => isProcessing = false);
    }
  }


  Future<String> getPackageName() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.packageName;
    } catch (e) {
      print('Error getting package name: $e');
      return 'com.example.clean_guru'; // Fallback to your app's package name
    }
  }
  Future<Directory> getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/Cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<int> _cleanDirectory(Directory directory, List<String> extensions) async {
    int freedSpace = 0;
    try {
      if (await directory.exists()) {
        // Change this to recursive: true to scan subdirectories
        await for (var entity in directory.list(recursive: true)) {
          if (entity is File) {
            try {
              // If extensions list is empty, delete all files
              // Otherwise, check if file matches any of the specified extensions
              if (extensions.isEmpty ||
                  extensions.any((ext) => entity.path.toLowerCase().endsWith(ext))) {
                int fileSize = await entity.length();
                await entity.delete();
                freedSpace += fileSize;
                print('Deleted: ${entity.path} (${fileSize / 1024} KB)');
              }
            } catch (e) {
              print('Error deleting file ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error cleaning directory ${directory.path}: $e');
    }
    return freedSpace;
  }

  Future<int> _getDirSize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (var entity in dir.list(recursive: true)) {
          if (entity is File) {
            try {
              size += await entity.length();
            } catch (e) {
              print('Error getting file size: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error calculating directory size: $e');
    }
    return size;
  }

  Widget _buildMaintenanceCard({
    required String title,
    required String description,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      color: const Color(0xFFFCFCFC), // Setting the card background color to #FCFCFC
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: double.infinity, // This ensures the card takes full width available
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, // Make button take full width
              child: ElevatedButton(
                onPressed: isProcessing ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.blue[400]!),
                  ),
                  backgroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 40), // Full width, 40 height
                ),
                child: Text(
                  buttonText,
                  style: TextStyle(
                    color: Colors.blue[400],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> generateTestCacheFiles() async {
    try {
      // Get directories your app can access
      final tempDir = await getTemporaryDirectory();
      final appDir = await getApplicationDocumentsDirectory();
      final externalDir = await getExternalStorageDirectory();

      // Create various sized cache files
      await _createDummyCacheFiles(tempDir, 10, 500 * 1024); // 10 files, 500KB each
      await _createDummyCacheFiles(appDir, 5, 1024 * 1024); // 5 files, 1MB each

      if (externalDir != null) {
        // Create a "cache" subdirectory in the external storage
        final externalCacheDir = Directory('${externalDir.path}/cache');
        if (!await externalCacheDir.exists()) {
          await externalCacheDir.create(recursive: true);
        }
        await _createDummyCacheFiles(externalCacheDir, 3, 2 * 1024 * 1024); // 3 files, 2MB each
      }

      // Show success message
      Fluttertoast.showToast(
        msg: 'Created test cache files',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
      );
    } catch (e) {
      print('Error creating test cache files: $e');
      Fluttertoast.showToast(
        msg: 'Error creating test files: $e',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _createDummyCacheFiles(Directory dir, int count, int size) async {
    for (int i = 0; i < count; i++) {
      final file = File('${dir.path}/test_cache_${i}_${DateTime.now().millisecondsSinceEpoch}.cache');
      final randomData = List.generate(size, (_) => Random().nextInt(256));
      await file.writeAsBytes(randomData);
    }
  }


  Future<void> _createTestJunkFiles() async {
    try {
      // Request storage permissions first
      if (!await Permission.storage.isGranted) {
        await _requestPermissions();
        return;
      }

      // Get various directories to create test junk files
      final directories = [
        await getApplicationDocumentsDirectory(),
        await getTemporaryDirectory(),
        await getExternalStorageDirectory(),
        Directory('/storage/emulated/0/Download')
      ];

      // List of junk file extensions and sizes
      final junkFiles = [
        ('.tmp', 512 * 1024),    // 512 KB temporary file
        ('.log', 256 * 1024),    // 256 KB log file
        ('.old', 128 * 1024),    // 128 KB old file
        ('.bak', 64 * 1024),     // 64 KB backup file
        ('.cache', 32 * 1024)    // 32 KB cache file
      ];

      int totalJunkCreated = 0;

      // Create junk files in each directory
      for (var directory in directories) {
        if (directory == null || !await directory.exists()) continue;

        for (var (extension, size) in junkFiles) {
          final junkFile = File('${directory.path}/test_junk_file_${DateTime.now().millisecondsSinceEpoch}$extension');

          try {
            // Create file with random content
            await junkFile.create();
            final randomContent = List.generate(size, (_) => 'A');
            await junkFile.writeAsString(randomContent.join());

            totalJunkCreated += size;

            print('Created junk file: ${junkFile.path} - ${size} bytes');
          } catch (e) {
            print('Error creating junk file: $e');
          }
        }
      }

      // Show toast or dialog to confirm
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Created ${(totalJunkCreated / 1024).toStringAsFixed(2)} KB of test junk files',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error creating test files: $e',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  Future<void> _deleteTestJunkFiles() async {
    try {
      // Get various directories
      final directories = [
        await getApplicationDocumentsDirectory(),
        await getTemporaryDirectory(),
        await getExternalStorageDirectory(),
        Directory('/storage/emulated/0/Download')
      ];

      int filesDeleted = 0;
      int totalSpaceFreed = 0;

      for (var directory in directories) {
        if (directory == null || !await directory.exists()) continue;

        await for (var entity in directory.list(recursive: false)) {
          if (entity is File &&
              (entity.path.contains('test_junk_file_') &&
                  (entity.path.endsWith('.tmp') ||
                      entity.path.endsWith('.log') ||
                      entity.path.endsWith('.old') ||
                      entity.path.endsWith('.bak') ||
                      entity.path.endsWith('.cache')))) {

            final fileSize = await entity.length();
            await entity.delete();

            filesDeleted++;
            totalSpaceFreed += fileSize;
          }
        }
      }

      // Show toast or dialog to confirm
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Deleted $filesDeleted test junk files (${(totalSpaceFreed / 1024).toStringAsFixed(2)} KB)',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error deleting test files: $e',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    // Create translations map
    final translations = {
      'system_maintenance': isEnglish ? 'System Maintenance' : 'صيانة النظام',
      'clean_up_organize': isEnglish ? 'Clean up and organize your system for better performance.' : 'تنظيف وتنظيم نظامك لتحسين الأداء.',
      'junk_file_removal': isEnglish ? 'Junk File Removal' : 'إزالة الملفات غير المرغوب فيها',
      'free_up_space': isEnglish ? 'Free Up Space By Deleting Unnecessary Files.' : 'تحرير مساحة بحذف الملفات غير الضرورية.',
      'remove_junk': isEnglish ? 'Remove Junk' : 'إزالة الملفات غير المرغوب فيها',
      'temp_file_cleanup': isEnglish ? 'Temporary File Cleanup' : 'تنظيف الملفات المؤقتة',
      'clear_temp_files': isEnglish ? 'Clear Temporary Files To Enhance System Performance.' : 'مسح الملفات المؤقتة لتعزيز أداء النظام.',
      'clean_temp_files': isEnglish ? 'Clean Temporary Files' : 'تنظيف الملفات المؤقتة',
      'download_organization': isEnglish ? 'Download Folder Organization' : 'تنظيم مجلد التنزيلات',
      'sort_organize': isEnglish ? 'Sort And Organize Your Downloaded Files.' : 'فرز وتنظيم ملفاتك التي تم تنزيلها.',
      'organize_downloads': isEnglish ? 'Organize Downloads' : 'تنظيم التنزيلات',
      'cache_management': isEnglish ? 'System Cache Management' : 'إدارة ذاكرة التخزين المؤقت للنظام',
      'remove_cache': isEnglish ? 'Remove Cache Files For Smoother Performance.' : 'إزالة ملفات التخزين المؤقت للحصول على أداء أكثر سلاسة.',
      'clear_cache': isEnglish ? 'Clear Cache' : 'مسح ذاكرة التخزين المؤقت',
      // Dialog translations
      'junk_file_removal_title': isEnglish ? 'Junk File Removal' : 'إزالة الملفات غير المرغوب فيها',
      'junk_file_found': isEnglish ? 'MB of junk files are found.' : 'ميجابايت من الملفات غير المرغوب فيها تم العثور عليها.',
      'cancel': isEnglish ? 'Cancel' : 'إلغاء',
      'delete': isEnglish ? 'Delete' : 'حذف',
      'operation_cancelled': isEnglish ? 'Operation cancelled' : 'تم إلغاء العملية',
      'starting_cleanup': isEnglish ? 'Starting cleanup...' : 'بدء التنظيف...',
      'freed_space': isEnglish ? 'Freed' : 'تم تحرير',
      'of_space': isEnglish ? 'MB of space' : 'ميجابايت من المساحة',
      'error': isEnglish ? 'Error:' : 'خطأ:',
      'temp_file_cleanup_title': isEnglish ? 'Temporary File Cleanup' : 'تنظيف الملفات المؤقتة',
      'clean_leftover': isEnglish ? 'Clean leftover app data.' : 'تنظيف بيانات التطبيق المتبقية.',
      'clean_now': isEnglish ? 'Clean Now' : 'نظف الآن',
      'cleaned': isEnglish ? 'Cleaned' : 'تم تنظيف',
      'of_temp_files': isEnglish ? 'MB of temporary files' : 'ميجابايت من الملفات المؤقتة',
      'download_title': isEnglish ? 'Download Folder Organization' : 'تنظيم مجلد التنزيلات',
      'file_recognized': isEnglish ? 'file recognized' : 'ملف تم التعرف عليه',
      'organize_now': isEnglish ? 'Organize Now' : 'نظم الآن',
      'download_not_found': isEnglish ? 'Download directory not found' : 'لم يتم العثور على مجلد التنزيلات',
      'organized': isEnglish ? 'Organized' : 'تم تنظيم',
      'files_successfully': isEnglish ? 'files successfully' : 'ملف بنجاح',
      'cache_title': isEnglish ? 'System Cache Management' : 'إدارة ذاكرة التخزين المؤقت للنظام',
      'cache_analyzed': isEnglish ? 'Cache size analyzed per system area' : 'تم تحليل حجم ذاكرة التخزين المؤقت لكل منطقة في النظام',
      'clear_all_cache': isEnglish ? 'Clear All Cache' : 'مسح كل ذاكرة التخزين المؤقت',
      'cleared': isEnglish ? 'Successfully cleared' : 'تم مسح',
      'of_cache': isEnglish ? 'MB of cache' : 'ميجابايت من ذاكرة التخزين المؤقت',
      'partial_cache': isEnglish ? 'Partial cache clearing. Failed to clear:' : 'مسح جزئي لذاكرة التخزين المؤقت. فشل في مسح:',
      'error_cache': isEnglish ? 'Error during cache clearing:' : 'خطأ أثناء مسح ذاكرة التخزين المؤقت:',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(translations['system_maintenance']!),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () => _generateTestCacheFiles(context),
                icon: Icon(Icons.bug_report, size: 20),
                label: Text(isEnglish ? 'Create Test Files' : 'إنشاء ملفات اختبار'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    translations['system_maintenance']!,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    translations['clean_up_organize']!,
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            _buildMaintenanceCard(
              title: translations['junk_file_removal']!,
              description: translations['free_up_space']!,
              buttonText: translations['remove_junk']!,
              onPressed: () => _removeJunkFiles(translations),
            ),

            _buildMaintenanceCard(
              title: translations['temp_file_cleanup']!,
              description: translations['clear_temp_files']!,
              buttonText: translations['clean_temp_files']!,
              onPressed: () => _cleanTemporaryFiles(translations),
            ),
          /*  _buildMaintenanceCard(
              title: translations['download_organization']!,
              description: translations['sort_organize']!,
              buttonText: translations['organize_downloads']!,
              onPressed: () => _organizeDownloads(translations),
            ),*/
           /* _buildMaintenanceCard(
              title: translations['cache_management']!,
              description: translations['remove_cache']!,
              buttonText: translations['clear_cache']!,
              onPressed: () => _clearCache(translations),
            ),*/

            _buildMaintenanceCard(
              title: translations['browser_cache_management'] ?? 'Browser Cache Management',
              description: translations['remove_browser_cache'] ?? 'Clear browser cache files for faster browsing.',
              buttonText: translations['clear_browser_cache'] ?? 'Clear Browser Cache',
              onPressed: () => _clearBrowserCache(translations),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateTestCacheFiles(BuildContext context) async {
    try {
      // Show a loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Creating test files...'),
          duration: Duration(seconds: 1),
        ),
      );

      // Get directories your app can access - with null safety checks
      Directory? tempDir;
      Directory? appDir;
      Directory? externalDir;

      try {
        tempDir = await getTemporaryDirectory();
      } catch (e) {
        print('Could not get temp directory: $e');
      }

      try {
        appDir = await getApplicationDocumentsDirectory();
      } catch (e) {
        print('Could not get app documents directory: $e');
      }

      try {
        externalDir = await getExternalStorageDirectory();
      } catch (e) {
        print('Could not get external storage directory: $e');
      }

      int totalFilesCreated = 0;
      int totalSizeCreated = 0;

      // Create test files in temp directory
      if (tempDir != null) {
        final result = await _createTestFiles(
            tempDir,
            5,  // Number of files
            200 * 1024,  // Size per file (200KB)
            ['.cache', '.tmp']  // Extensions to use
        );
        totalFilesCreated += result['count']!;
        totalSizeCreated += result['size']!;
      }

      // Create test files in app directory
      if (appDir != null) {
        final result = await _createTestFiles(
            appDir,
            3,  // Number of files
            300 * 1024,  // Size per file (300KB)
            ['.log', '.bak']  // Extensions to use
        );
        totalFilesCreated += result['count']!;
        totalSizeCreated += result['size']!;
      }

      // Create test files in external directory
      if (externalDir != null) {
        final result = await _createTestFiles(
            externalDir,
            2,  // Number of files
            500 * 1024,  // Size per file (500KB)
            ['.cache', '.tmp']  // Extensions to use
        );
        totalFilesCreated += result['count']!;
        totalSizeCreated += result['size']!;
      }

      // Show success message with size in MB
      final totalMB = (totalSizeCreated / (1024 * 1024)).toStringAsFixed(2);
      Fluttertoast.showToast(
        msg: 'Created $totalFilesCreated test files ($totalMB MB)',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
        textColor: Colors.white,
      );
    } catch (e) {
      print('Error creating test cache files: $e');
      Fluttertoast.showToast(
        msg: 'Error: $e',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }


  Future<Map<String, int>> _createTestFiles(
      Directory dir,
      int count,
      int sizePerFile,
      List<String> extensions
      ) async {
    int filesCreated = 0;
    int totalSize = 0;

    try {
      final random = Random();

      for (int i = 0; i < count; i++) {
        // Pick a random extension from the list
        final extension = extensions[random.nextInt(extensions.length)];

        // Create a unique filename
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filename = 'test_file_${i}_${timestamp}$extension';
        final filePath = '${dir.path}/$filename';

        try {
          // Create file and write random data
          final file = File(filePath);

          // Instead of generating a huge list, write in chunks to avoid memory issues
          final fileSize = sizePerFile - random.nextInt(sizePerFile ~/ 4); // Vary size slightly
          final outputStream = file.openWrite();

          // Write in chunks of 4KB
          const chunkSize = 4 * 1024;
          int remainingBytes = fileSize;

          while (remainingBytes > 0) {
            final bytesToWrite = remainingBytes > chunkSize ? chunkSize : remainingBytes;
            final chunk = List.generate(bytesToWrite, (_) => random.nextInt(256));
            outputStream.add(chunk);
            remainingBytes -= bytesToWrite;
          }

          await outputStream.close();

          filesCreated++;
          totalSize += fileSize;
          print('Created: $filePath (${fileSize / 1024} KB)');
        } catch (e) {
          print('Error creating test file $filename: $e');
        }
      }
    } catch (e) {
      print('Error in _createTestFiles for ${dir.path}: $e');
    }

    return {
      'count': filesCreated,
      'size': totalSize,
    };
  }

}

