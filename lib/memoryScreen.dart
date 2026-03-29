import 'dart:async';

import 'package:clean_guru/unnusedAppInfo.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:clean_guru/languageProvider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({Key? key}) : super(key: key);

  @override
  _MemoryScreenState createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> with WidgetsBindingObserver{
  static const platform = MethodChannel('com.arabapps.cleangru/memory');
  bool showRamUsage = false;
  bool isOptimizing = false;
  bool isLoadingApps = false;
  int selectedCount = 3;
  Set<String> recentlyClosedPackages = {};
  List<String> _closedAppPackages = [];
  DateTime _lastCleanTime = DateTime.now().subtract(Duration(days: 1)); // Initialize to yesterday
  Map<String, bool> selections = {
    'Clean RAM': true,
    'Performance Monitoring': true,
    'Optimize App Usage': true,
    'Manage Background Processes': true,
  };
  Map<String, DateTime> _cleanedApps = {}; // Track when apps were cleaned

  Map<String, dynamic> optimizationResults = {
    'freedMemory': 0,
    'cpuUsage': 0.0,
    'memoryUsage': 0.0,
    'optimizedApps': 0,
    'terminatedProcesses': 0,
    'totalRam': 0,
    'usedRam': 0,
    'freeRam': 0,
  };

  List<AppRamUsage> apps = [];
  List<UnusedAppInfo> unusedApps = [];
  bool _justCleaned = false;


  @override
  void initState() {
    super.initState();

    // Update selections map without Clean RAM
    selections = {
      'Performance Monitoring': true,
      'Optimize App Usage': true,
      'Manage Background Processes': true,
    };

    // Count selected options initially
    selectedCount = selections.values.where((v) => v).length;

    // Add an app lifecycle listener
    WidgetsBinding.instance.addObserver(this);

    // Load saved cleaned apps list
    _loadCleanedAppsList();
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

// Add this method to detect when the app is resumed
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reset the flag when the app is resumed after being in background
      setState(() {
        _justCleaned = false;
      });

      // Also check for newly reopened apps
      _checkForNewBackgroundApps();

      // Hide the RAM usage screen if it was showing
      if (showRamUsage) {
        setState(() {
          showRamUsage = false;
        });
      }
    }
  }



  Future<void> cleanRAM() async {
    setState(() {
      isOptimizing = true;
    });

    try {
      // Get all apps to close
      final allApps = unusedApps.map((app) => app.packageName).toList();
      final appsCount = allApps.length;

      if (allApps.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No apps found to close'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => isOptimizing = false);
        return;
      }

      print("🧹 Cleaning apps: $allApps");

      // Record all apps being cleaned with current timestamp
      final now = DateTime.now();
      for (String packageName in allApps) {
        _cleanedApps[packageName] = now;
      }

      // Call native method to clean RAM
      final freedMemory = await platform.invokeMethod('cleanRAM', {
        'selectedApps': allApps,
      });

      // Wait a moment for apps to close
      await Future.delayed(Duration(milliseconds: 500));

      // Get updated metrics
      final metrics = await platform.invokeMethod('getPerformanceMetrics');

      // Standardize RAM values
      int totalRam = metrics['totalRam'] ?? 0;
      int usedRam = metrics['usedRam'] ?? 0;
      int freeRam = metrics['freeRam'] ?? 0;

      int standardTotalRam = standardizeRamValue(totalRam);
      double ratio = standardTotalRam / totalRam;
      int adjustedUsedRam = (usedRam * ratio).round();
      int adjustedFreeRam = standardTotalRam - adjustedUsedRam;

      setState(() {
        // Clear the list of apps
        unusedApps.clear();

        optimizationResults = {
          ...metrics,
          'totalRam': standardTotalRam,
          'usedRam': adjustedUsedRam,
          'freeRam': adjustedFreeRam,
          'freedMemory': freedMemory,
        };

        // Return to the main screen
        showRamUsage = false;
      });

      // Save the cleaned apps list to SharedPreferences for persistence
      _saveCleanedAppsList();

      // Show success message
      // Show simple success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Memory cleaned'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error cleaning RAM: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clean memory: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        isOptimizing = false;
      });
    }
  }

  Future<void> _saveCleanedAppsList() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      // Clear old data
      final keys = prefs.getKeys();
      for (String key in keys) {
        if (key.startsWith('cleaned_')) {
          await prefs.remove(key);
        }
      }

      // Save current cleaned apps
      for (String packageName in _cleanedApps.keys) {
        final timestamp = _cleanedApps[packageName]!.millisecondsSinceEpoch;
        await prefs.setInt('cleaned_$packageName', timestamp);
      }

      print("💾 Saved ${_cleanedApps.length} cleaned apps to preferences");
    } catch (e) {
      print("❌ Error saving cleaned apps: $e");
    }
  }
  Future<void> _loadCleanedAppsList() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _cleanedApps.clear();

      final keys = prefs.getKeys();
      for (String key in keys) {
        if (key.startsWith('cleaned_')) {
          final packageName = key.substring(8); // Remove 'cleaned_'
          final timestamp = prefs.getInt(key);
          if (timestamp != null) {
            _cleanedApps[packageName] = DateTime.fromMillisecondsSinceEpoch(timestamp);
          }
        }
      }

      print("📂 Loaded ${_cleanedApps.length} cleaned apps from preferences");
    } catch (e) {
      print("❌ Error loading cleaned apps: $e");
    }
  }


// Fix fetchRecentlyUsedApps to check if memory was already cleaned
  Future<void> fetchRecentlyUsedApps() async {
    print("⭐ Fetching recently used apps...");
    setState(() {
      isLoadingApps = true;
    });

    // Get the language provider for translations
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    final translations = {
      'no_background_apps': isEnglish ? 'No background apps found - memory already optimized!' : 'لم يتم العثور على تطبيقات خلفية - تم تحسين الذاكرة بالفعل!',
      'error_getting_apps': isEnglish ? 'Error getting apps: ' : 'خطأ في الحصول على التطبيقات: ',
      'using_demo_data': isEnglish ? 'Using demo data: ' : 'استخدام بيانات تجريبية: ',
    };

    // First check if memory was just cleaned
    if (_justCleaned) {
      print("⭐ Skipping app fetch - memory was just cleaned");
      setState(() {
        unusedApps.clear(); // Make sure list is empty
        isLoadingApps = false;
      });
      return;
    }

    try {
      // Call the improved native method
      final List<dynamic> backgroundApps = await platform.invokeMethod('getRecentlyUsedApps');

      print("⭐ Received ${backgroundApps.length} apps from platform");

      // Check if we need permission
      if (backgroundApps.length == 1 && backgroundApps[0].containsKey('permissionNeeded')) {
        // Need to request permission
        bool hasPermission = await platform.invokeMethod('checkUsagePermission');
        if (!hasPermission) {
          // Ask for permission
          await platform.invokeMethod('openUsageSettings');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please grant usage access permission')),
          );
        }
        _setDefaultRunningApps();
        return;
      }

      if (backgroundApps.isNotEmpty) {
        setState(() {
          // Clear the existing list
          unusedApps.clear();

          // Convert the returned data to UnusedAppInfo objects
          for (var app in backgroundApps) {
            unusedApps.add(UnusedAppInfo(
              name: app['name'] ?? 'Unknown App',
              packageName: app['packageName'] ?? '',
              ramUsage: formatMemorySize(app['ramUsage'] ?? 100000000),
              lastUsed: app['lastUsed'] != null ?
              DateTime.fromMillisecondsSinceEpoch(app['lastUsed']) :
              DateTime.now(),
              daysSinceUsed: 0,
              isSelected: true,
            ));
          }
        });
      }
      else {
        // If no apps returned, show a message that all apps have been cleared
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translations['no_background_apps']!)),
        );
        setState(() {
          unusedApps.clear();
          showRamUsage = false; // Go back to main screen since there's nothing to show
        });
      }
    } catch (e) {
      print("❌ Error fetching recently used apps: $e");
      // Fallback to example apps if fetch fails
      _setDefaultRunningApps();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(translations['using_demo_data']! + e.toString())),
        );
      }
    } finally {
      setState(() {
        isLoadingApps = false;
      });
    }
  }

  Future<void> fetchRunningApps() async {
    print("⭐ Fetching background apps...");
    setState(() {
      isLoadingApps = true;
    });

    try {
      // Call native method to get running apps
      final List<dynamic> runningApps = await platform.invokeMethod('getRunningApps');

      print("⭐ Received ${runningApps.length} apps from platform");
      if (runningApps.isNotEmpty) {
        setState(() {
          // Clear the existing list of unused apps
          unusedApps.clear();

          // Convert the returned data to UnusedAppInfo objects
          for (var app in runningApps) {
            final String name = app['name'] ?? 'Unknown App';
            final String packageName = app['packageName'] ?? '';
            final int ramUsage = app['ramUsage'] ?? 100_000_000; // Default 100MB if not provided

            unusedApps.add(UnusedAppInfo(
              name: name,
              packageName: packageName,
              ramUsage: formatMemorySize(ramUsage),
              lastUsed: DateTime.now(), // These are running apps so "last used" is now
              daysSinceUsed: 0,
              isSelected: true,
            ));
          }
        });
      }
      else {
        // If no apps returned, use default list
        print("⭐ No apps returned from platform, using default list");
        _setDefaultRunningApps();
      }
    } catch (e) {
      print("❌ Error fetching running apps: $e");
      // Fallback to example apps if fetch fails
      _setDefaultRunningApps();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Using demo data: $e')),
        );
      }
    } finally {
      setState(() {
        isLoadingApps = false;
      });
    }
  }
  Future<void> fetchInstalledApps() async {
    print("⭐ Fetching installed apps...");
    setState(() {
      isLoadingApps = true;
    });

    try {
      // Call native method to get installed apps
      final List<dynamic> installedApps = await platform.invokeMethod('getInstalledApps');

      print("⭐ Received ${installedApps.length} apps from platform");

      if (installedApps.isNotEmpty) {
        setState(() {
          // Clear the existing list
          unusedApps.clear();

          // Convert the returned data to UnusedAppInfo objects
          for (var app in installedApps) {
            unusedApps.add(UnusedAppInfo(
              name: app['name'] ?? 'Unknown App',
              packageName: app['packageName'] ?? '',
              ramUsage: formatMemorySize(app['ramUsage'] ?? 100000000),
              lastUsed: DateTime.now(),
              daysSinceUsed: 0,
              isSelected: true,
            ));
          }
        });
      }
      else {
        // If no apps returned, use default list
        print("⭐ No apps returned from platform, using default list");
       // _setDefaultInstalledApps();
      }
    } catch (e) {
      print("❌ Error fetching installed apps: $e");
      // Fallback to example apps if fetch fails
      //_setDefaultInstalledApps();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Using demo data: $e')),
        );
      }
    } finally {
      setState(() {
        isLoadingApps = false;
      });
    }
  }
// Add this method to provide realistic defaults for running apps
  void _setDefaultRunningApps() {
    final now = DateTime.now();

    unusedApps = [
      UnusedAppInfo(
        name: 'Facebook',
        packageName: 'com.facebook.katana',
        ramUsage: '180 MB',
        lastUsed: now,
        daysSinceUsed: 0,
        isSelected: true,
      ),
      UnusedAppInfo(
        name: 'Chrome',
        packageName: 'com.android.chrome',
        ramUsage: '210 MB',
        lastUsed: now,
        daysSinceUsed: 0,
        isSelected: true,
      ),
      UnusedAppInfo(
        name: 'WhatsApp',
        packageName: 'com.whatsapp',
        ramUsage: '145 MB',
        lastUsed: now,
        daysSinceUsed: 0,
        isSelected: true,
      ),
      UnusedAppInfo(
        name: 'Instagram',
        packageName: 'com.instagram.android',
        ramUsage: '165 MB',
        lastUsed: now,
        daysSinceUsed: 0,
        isSelected: true,
      ),
      UnusedAppInfo(
        name: 'Twitter',
        packageName: 'com.twitter.android',
        ramUsage: '120 MB',
        lastUsed: now,
        daysSinceUsed: 0,
        isSelected: true,
      ),
    ];
  }


  Future<List<AppRamUsage>> getSimulatedBackgroundApps() async {
    List<AppRamUsage> backgroundApps = [];

    try {
      // Create a list of common apps people might have
      final commonApps = [
        {"name": "WhatsApp", "package": "com.whatsapp", "icon": Icons.message},
        {"name": "Chrome", "package": "com.android.chrome", "icon": Icons.web},
        {"name": "YouTube", "package": "com.google.android.youtube", "icon": Icons.play_arrow},
        {"name": "Gmail", "package": "com.google.android.gm", "icon": Icons.mail},
        {"name": "Maps", "package": "com.google.android.maps", "icon": Icons.map},
        {"name": "Instagram", "package": "com.instagram.android", "icon": Icons.camera_alt},
        {"name": "Facebook", "package": "com.facebook.katana", "icon": Icons.facebook},
        {"name": "Twitter", "package": "com.twitter.android", "icon": Icons.public},
        {"name": "Spotify", "package": "com.spotify.music", "icon": Icons.music_note},
        {"name": "Netflix", "package": "com.netflix.mediaclient", "icon": Icons.movie},
        {"name": "TikTok", "package": "com.zhiliaoapp.musically", "icon": Icons.music_video},
        {"name": "Snapchat", "package": "com.snapchat.android", "icon": Icons.camera},
      ];

      // Randomly select 5-8 apps to show as "background" apps
      commonApps.shuffle();
      final appsToShow = commonApps.take(5 + (DateTime.now().millisecond % 4));

      for (var app in appsToShow) {
        // Generate random RAM usage between 80-250MB
        final randomRam = 80 + (app["name"].hashCode % 170);
        final ramInBytes = randomRam * 1024 * 1024;

        backgroundApps.add(AppRamUsage(
          name: app["name"] as String,
          ramUsage: formatMemorySize(ramInBytes),
          icon: app["icon"] as IconData,
          packageName: app["package"] as String,
          isSelected: true,
        ));
      }
    } catch (e) {
      print('Error simulating background apps: $e');
    }

    return backgroundApps;
  }

  Future<bool> verifyBackgroundApps() async {
    setState(() {
      isLoadingApps = true;
    });

    try {
      // Get all background apps without any filtering
      final List<dynamic> backgroundApps = await platform.invokeMethod('getRecentlyUsedApps');

      print("⭐ Received ${backgroundApps.length} total background apps");

      // Check if we need permission
      if (backgroundApps.length == 1 && backgroundApps[0].containsKey('permissionNeeded')) {
        // Need to request permission
        bool hasPermission = await platform.invokeMethod('checkUsagePermission');
        if (!hasPermission) {
          await platform.invokeMethod('openUsageSettings');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please grant usage access permission')),
          );
        }
        setState(() {
          unusedApps.clear();
          isLoadingApps = false;
        });
        return false;
      }

      // Get timestamp of last time each app was used (active usage, not just background)
      final Map<String, int> lastUsedMap = await _getLastActiveUsageTimes();
      print("⭐ Retrieved ${lastUsedMap.length} last used timestamps");

      // Update the unusedApps list, filtering out apps we've cleaned that haven't been reopened
      setState(() {
        unusedApps.clear();

        // Process all detected background apps
        if (backgroundApps.isNotEmpty) {
          for (var app in backgroundApps) {
            final String packageName = app['packageName'] ?? '';

            // Skip system apps and our own app
            if (packageName == 'com.example.clean_guru') {
              continue;
            }

            // Check if this app was previously cleaned
            if (_cleanedApps.containsKey(packageName)) {
              final cleanTime = _cleanedApps[packageName]!;

              // Check if it was manually reopened by the user since we cleaned it
              final lastUsedMillis = lastUsedMap[packageName] ?? 0;
              if (lastUsedMillis > 0) {
                final lastUsedTime = DateTime.fromMillisecondsSinceEpoch(lastUsedMillis);

                // If the app was used after we cleaned it, include it
                if (lastUsedTime.isAfter(cleanTime)) {
                  print("⭐ App was reopened by user after cleaning: $packageName");
                  // Remove from cleaned list since user has reopened it
                  _cleanedApps.remove(packageName);
                } else {
                  // App was cleaned and not reopened by user, skip it
                  print("⭐ Filtering cleaned app: $packageName");
                  continue;
                }
              } else {
                // No usage data, safer to skip
                print("⭐ No usage data for cleaned app: $packageName");
                continue;
              }
            }

            // Add the app to our list
            unusedApps.add(UnusedAppInfo(
              name: app['name'] ?? 'Unknown App',
              packageName: packageName,
              ramUsage: formatMemorySize(app['ramUsage'] ?? 100000000),
              lastUsed: DateTime.now(),
              daysSinceUsed: 0,
              isSelected: true,
            ));
          }
        }
      });

      print("⭐ Found ${unusedApps.length} apps to show after filtering");
      return true;
    } catch (e) {
      print("❌ Error verifying background apps: $e");
      setState(() {
        unusedApps.clear();
        isLoadingApps = false;
      });
      return false;
    } finally {
      setState(() {
        isLoadingApps = false;
      });
    }
  }

  Future<Map<String, int>> _getLastActiveUsageTimes() async {
    try {
      final List<dynamic> usageTimes = await platform.invokeMethod('getAppLastUsageTimes');
      final Map<String, int> result = {};

      for (var item in usageTimes) {
        final String packageName = item['packageName'] ?? '';
        final int lastUsed = item['lastUsed'] ?? 0;
        if (packageName.isNotEmpty && lastUsed > 0) {
          result[packageName] = lastUsed;
        }
      }

      return result;
    } catch (e) {
      print("❌ Error getting usage times: $e");
      return {};
    }
  }

  Future<void> _checkForNewBackgroundApps() async {
    // We'll only do this check if the user had cleaned apps recently
    if (_closedAppPackages.isEmpty) return;

    // This will be called periodically to check if closed apps have been reopened
    print("⭐ Checking for newly reopened apps...");

    // Only perform this check if we're on the main screen (not the RAM screen)
    if (showRamUsage) return;

    try {
      // Call the native method to get current running apps
      final List<dynamic> runningApps = await platform.invokeMethod('getRecentlyUsedApps');

      // Check if any of our closed apps are now running again
      bool foundReopenedApp = false;

      for (var app in runningApps) {
        final String packageName = app['packageName'] ?? '';
        if (_closedAppPackages.contains(packageName)) {
          print("⭐ Previously closed app is now running again: $packageName");
          foundReopenedApp = true;

          // Remove this app from our closed tracking
          _closedAppPackages.remove(packageName);
          recentlyClosedPackages.remove(packageName);

          // Also remove from SharedPreferences
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.remove('closed_$packageName');
        }
      }

      // If we found reopened apps, let the user know
      if (foundReopenedApp && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Previously closed apps are now running again'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("❌ Error checking for reopened apps: $e");
    }
  }


  Future<void> startOptimization() async {
    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    // Create translations for error messages
    final messages = {
      'select_one_option': isEnglish ? 'Please select at least one optimization option' : 'الرجاء تحديد خيار تحسين واحد على الأقل',
      'memory_optimized': isEnglish ? 'Memory already optimized! Please wait a while before optimizing again.' : 'تم تحسين الذاكرة بالفعل! يرجى الانتظار قليلاً قبل التحسين مرة أخرى.',
      'no_background_apps': isEnglish ? 'No apps found running in the background' : 'لم يتم العثور على تطبيقات خلفية',
      'failed_metrics': isEnglish ? 'Failed to get performance metrics: ' : 'فشل في الحصول على مقاييس الأداء: ',
      'checking_apps': isEnglish ? 'Checking for background apps...' : 'جارٍ التحقق من التطبيقات الخلفية...',
    };

    // Validate selection
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messages['select_one_option']!)),
      );
      return;
    }

    // If we just cleaned the memory, show an already cleaned message
    if (_justCleaned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(messages['memory_optimized']!),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    setState(() {
      isOptimizing = true;
    });

    // Show a message that we're checking for apps
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(messages['checking_apps']!),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      // Get initial performance metrics from platform
      final metrics = await platform.invokeMethod('getPerformanceMetrics');

      // Standardize RAM values
      int totalRam = metrics['totalRam'] ?? 0;
      int usedRam = metrics['usedRam'] ?? 0;
      int freeRam = metrics['freeRam'] ?? 0;

      // Apply standard rounding to total RAM
      int standardTotalRam = standardizeRamValue(totalRam);

      // Adjust used and free RAM proportionally to maintain consistency
      double ratio = standardTotalRam / totalRam;
      int adjustedUsedRam = (usedRam * ratio).round();
      int adjustedFreeRam = standardTotalRam - adjustedUsedRam;

      setState(() {
        optimizationResults = {
          ...metrics,
          'totalRam': standardTotalRam,
          'usedRam': adjustedUsedRam,
          'freeRam': adjustedFreeRam,
          'freedMemory': 0, // Reset freedMemory
        };
      });

      // Check for background apps
      await verifyBackgroundApps();

      // IMPORTANT: Only show the RAM usage screen if we actually found apps
      if (unusedApps.isEmpty) {
        // No apps found, show message and stay on main screen
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(messages['no_background_apps']!),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Make sure we're on the main screen
        setState(() {
          showRamUsage = false;
        });
      } else {
        // We found apps, show the RAM usage screen
        setState(() {
          showRamUsage = true;
        });
      }
    } catch (e) {
      print('Error getting metrics: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messages['failed_metrics']! + e.toString())),
      );
    } finally {
      setState(() => isOptimizing = false);
    }
  }



  int standardizeRamValue(int bytes) {
    double gbValue = bytes / (1024 * 1024 * 1024);

    if (gbValue > 6.0 && gbValue < 10.0) {
      return 8 * 1024 * 1024 * 1024; // 8 GB in bytes
    } else if (gbValue > 14.0 && gbValue < 18.0) {
      return 16 * 1024 * 1024 * 1024; // 16 GB in bytes
    } else if (gbValue > 28.0 && gbValue < 34.0) {
      return 32 * 1024 * 1024 * 1024; // 32 GB in bytes
    } else if (gbValue > 60.0 && gbValue < 68.0) {
      return 64 * 1024 * 1024 * 1024; // 64 GB in bytes
    } else {
      // Round to nearest GB for other values
      int roundedGB = gbValue.round();
      return roundedGB * 1024 * 1024 * 1024;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the language provider using Provider
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    // Create translations map
    final translations = {
      'memory_optimization': isEnglish ? 'Memory Optimization' : 'تحسين الذاكرة',
      'optimize_ram_usage': isEnglish ? 'Optimize RAM Usage' : 'تحسين استخدام ذاكرة الوصول العشوائي',
      'optimize_memory': isEnglish ? 'Optimize Memory' : 'تحسين الذاكرة',
      'clean_manage_monitor': isEnglish ? 'Clean, manage, and monitor memory for peak performance.' : 'تنظيف وإدارة ومراقبة الذاكرة للحصول على أفضل أداء.',
      'process_selected': isEnglish ? 'Process selected' : 'العمليات المحددة',
      'deselect_all': isEnglish ? 'Deselect All' : 'إلغاء تحديد الكل',
      'clean_ram': isEnglish ? 'Clean RAM' : 'تنظيف ذاكرة الوصول العشوائي',
      'clean_ram_desc': isEnglish ? 'Automatically Closes Unnecessary Processes.' : 'يغلق تلقائيًا العمليات غير الضرورية.',
      'performance_monitoring': isEnglish ? 'Performance Monitoring' : 'مراقبة الأداء',
      'performance_monitoring_desc': isEnglish ? 'Enables Real-Time Tracking Of CPU And Memory Performance.' : 'يمكّن التتبع في الوقت الحقيقي لأداء وحدة المعالجة المركزية والذاكرة.',
      'optimize_app_usage': isEnglish ? 'Optimize App Usage' : 'تحسين استخدام التطبيق',
      'optimize_app_usage_desc': isEnglish ? 'Identifies Rarely Used Apps For Pausing Or Optimization.' : 'يحدد التطبيقات نادرة الاستخدام للإيقاف المؤقت أو التحسين.',
      'manage_background': isEnglish ? 'Manage Background Processes' : 'إدارة العمليات الخلفية',
      'manage_background_desc': isEnglish ? 'Detects And Terminates Unnecessary Background Apps.' : 'يكتشف وينهي تطبيقات الخلفية غير الضرورية.',
      'start_optimization': isEnglish ? 'Start Optimization' : 'بدء التحسين',
      'optimizing': isEnglish ? 'Optimizing...' : 'جاري التحسين...',
      'background_apps': isEnglish ? 'Background Apps' : 'التطبيقات الخلفية',
      'select_apps_close': isEnglish ? 'Select apps you want to close to free up memory.' : 'حدد التطبيقات التي تريد إغلاقها لتحرير الذاكرة.',
      'total_ram': isEnglish ? 'Total RAM' : 'إجمالي ذاكرة الوصول العشوائي',
      'used_ram': isEnglish ? 'Used RAM' : 'ذاكرة الوصول العشوائي المستخدمة',
      'free_ram': isEnglish ? 'Free RAM' : 'ذاكرة الوصول العشوائي الحرة',
      'background_apps_found': isEnglish ? 'background apps found' : 'تم العثور على تطبيقات الخلفية',
      'clean_now': isEnglish ? 'Clean now' : 'تنظيف الآن',
      'cancel': isEnglish ? 'Cancel' : 'إلغاء',
      'select_clean_ram': isEnglish ? 'Please select Clean RAM to proceed' : 'الرجاء تحديد تنظيف ذاكرة الوصول العشوائي للمتابعة',
      'select_one_option': isEnglish ? 'Please select at least one optimization option' : 'الرجاء تحديد خيار تحسين واحد على الأقل',
      'memory_optimized': isEnglish ? 'Memory already optimized! Please wait a while before optimizing again.' : 'تم تحسين الذاكرة بالفعل! يرجى الانتظار قليلاً قبل التحسين مرة أخرى.',
      'no_background_apps': isEnglish ? 'No background apps found - memory already optimized!' : 'لم يتم العثور على تطبيقات خلفية - تم تحسين الذاكرة بالفعل!',
      'failed_metrics': isEnglish ? 'Failed to get performance metrics: ' : 'فشل في الحصول على مقاييس الأداء: ',
      // Add more translations as needed
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
       /* leading: IconButton(
          icon: Icon(showRamUsage ? Icons.close : Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (showRamUsage) {
              setState(() => showRamUsage = false);
            } else {
              Navigator.pop(context);
            }
          },
        ),*/
        title: Text(
          showRamUsage ? translations['optimize_ram_usage']! : translations['memory_optimization']!,
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: showRamUsage ? _buildUnusedAppsScreen(translations) : _buildOptimizationScreen(translations),
    );
  }

  IconData _getAppIconByCategory(String packageName) {
    if (packageName.contains('whatsapp')) return Icons.message;
    if (packageName.contains('instagram')) return Icons.camera_alt;
    if (packageName.contains('facebook')) return Icons.facebook;
    if (packageName.contains('twitter') || packageName.contains('.x.')) return Icons.public;
    if (packageName.contains('tiktok') || packageName.contains('musically')) return Icons.music_video;
    if (packageName.contains('snap')) return Icons.camera;
    if (packageName.contains('youtube')) return Icons.play_arrow;
    if (packageName.contains('chrome') || packageName.contains('browser')) return Icons.web;
    if (packageName.contains('gmail') || packageName.contains('mail')) return Icons.mail;
    if (packageName.contains('maps')) return Icons.map;
    if (packageName.contains('spotify') || packageName.contains('music')) return Icons.music_note;
    if (packageName.contains('netflix') || packageName.contains('video')) return Icons.movie;
    if (packageName.contains('game')) return Icons.games;
    if (packageName.contains('photo')) return Icons.photo;
    if (packageName.contains('shop') || packageName.contains('store')) return Icons.shopping_bag;
    if (packageName.contains('file') || packageName.contains('document')) return Icons.folder;

    // Default icon
    return Icons.android;
  }


  Widget _buildUnusedAppListItem(UnusedAppInfo app) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue.withOpacity(0.1),
        child: Icon(
          _getAppIconByName(app.name),
          color: Colors.blue,
        ),
      ),
      title: Text(app.name),
     /* subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
         // Text(app.ramUsage),
          // If we're showing background apps, we don't need to show "last used" time
          // You can remove or modify this as needed
        ],
      ),*/
      // Removed the trailing checkbox
    );
  }

  IconData _getAppIconByName(String appName) {
    final name = appName.toLowerCase();

    if (name.contains('game')) return Icons.games;
    if (name.contains('chat') || name.contains('message')) return Icons.chat;
    if (name.contains('photo') || name.contains('camera')) return Icons.photo_camera;
    if (name.contains('music') || name.contains('audio')) return Icons.music_note;
    if (name.contains('video')) return Icons.video_library;
    if (name.contains('map')) return Icons.map;
    if (name.contains('mail') || name.contains('email')) return Icons.email;
    if (name.contains('browser') || name.contains('chrome')) return Icons.web;
    if (name.contains('edit') || name.contains('note') || name.contains('text')) return Icons.edit;
    if (name.contains('file') || name.contains('document')) return Icons.description;

    return Icons.android;
  }


  Widget _buildUnusedAppsScreen(Map<String, String> translations) {
    // Get the language provider using Provider
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    // Create translations
    final translations = {
      'background_apps': isEnglish ? 'Background Apps' : 'التطبيقات الخلفية',
      'select_apps_close': isEnglish ? 'Apps to close to free up memory:' : 'التطبيقات لإغلاقها لتحرير الذاكرة:',
      'total_ram': isEnglish ? 'Total RAM' : 'إجمالي ذاكرة الوصول العشوائي',
      'used_ram': isEnglish ? 'Used RAM' : 'ذاكرة الوصول العشوائي المستخدمة',
      'free_ram': isEnglish ? 'Free RAM' : 'ذاكرة الوصول العشوائي الحرة',
      'background_apps_found': isEnglish ? 'background apps found' : 'تم العثور على تطبيقات خلفية',
      'no_apps_found': isEnglish ? 'No background apps found' : 'لم يتم العثور على تطبيقات خلفية',
      'clean_now': isEnglish ? 'Clean now' : 'تنظيف الآن',
      'cancel': isEnglish ? 'Cancel' : 'إلغاء',
      'return': isEnglish ? 'Return' : 'رجوع',
    };

    // Check if we actually have apps to show
    final bool hasApps = unusedApps.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translations['background_apps']!,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                hasApps
                    ? translations['select_apps_close']!
                    : translations['no_apps_found']!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildRamIndicator(
                        translations['total_ram']!,
                        formatMemorySize(optimizationResults['totalRam']?.toInt() ?? 0),
                        Colors.blue
                    ),
                    SizedBox(width: 24),
                    _buildRamIndicator(
                        translations['used_ram']!,
                        formatMemorySize(optimizationResults['usedRam']?.toInt() ?? 0),
                        Colors.red
                    ),
                    SizedBox(width: 24),
                    _buildRamIndicator(
                        translations['free_ram']!,
                        formatMemorySize(optimizationResults['freeRam']?.toInt() ?? 0),
                        Colors.green
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Only show app count if we have apps
        if (hasApps)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(
                  '${unusedApps.length} ${translations['background_apps_found']}',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

        isLoadingApps
            ? Center(child: CircularProgressIndicator())
            : hasApps
            ? Expanded(
          child: ListView.builder(
            itemCount: unusedApps.length,
            itemBuilder: (context, index) {
              return _buildUnusedAppListItem(unusedApps[index]);
            },
          ),
        )
            : Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Colors.green,
                ),
                SizedBox(height: 16),
                Text(
                  translations['no_apps_found']!,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              if (hasApps)
                Expanded(
                  child: ElevatedButton(
                    onPressed: isOptimizing ? null : cleanRAM,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: Size(0, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: isOptimizing
                        ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : Text(
                      translations['clean_now']!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (hasApps) SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => setState(() => showRamUsage = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.black,
                    minimumSize: Size(0, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: Text(
                    hasApps ? translations['cancel']! : translations['return']!,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildOptimizationScreen(Map<String, String> translations) {
    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    // Create translations for error messages
    final translations = {
      'optimize_memory': isEnglish ? 'Optimize Memory' : 'تحسين الذاكرة',
      'clean_manage_monitor': isEnglish ? 'Clean, manage, and monitor memory for peak performance.' : 'تنظيف وإدارة ومراقبة الذاكرة للحصول على أفضل أداء.',
      'performance_monitoring': isEnglish ? 'Performance Monitoring' : 'مراقبة الأداء',
      'performance_monitoring_desc': isEnglish ? 'Enables Real-Time Tracking Of CPU And Memory Performance.' : 'يمكّن التتبع في الوقت الحقيقي لأداء وحدة المعالجة المركزية والذاكرة.',
      'optimize_app_usage': isEnglish ? 'Optimize App Usage' : 'تحسين استخدام التطبيق',
      'optimize_app_usage_desc': isEnglish ? 'Identifies Rarely Used Apps For Pausing Or Optimization.' : 'يحدد التطبيقات نادرة الاستخدام للإيقاف المؤقت أو التحسين.',
      'manage_background': isEnglish ? 'Manage Background Processes' : 'إدارة العمليات الخلفية',
      'manage_background_desc': isEnglish ? 'Detects And Terminates Unnecessary Background Apps.' : 'يكتشف وينهي تطبيقات الخلفية غير الضرورية.',
      'start_optimization': isEnglish ? 'Start Optimization' : 'بدء التحسين',
      'optimizing': isEnglish ? 'Optimizing...' : 'جاري التحسين...',
    };

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translations['optimize_memory']!,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  translations['clean_manage_monitor']!,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            child: Column(
              children: [
                GridView.count(
                  physics: NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  crossAxisCount: 2,
                  childAspectRatio: 1.1,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    // Remove the Clean RAM option
                    _buildOptionCard(
                      translations['performance_monitoring']!,
                      translations['performance_monitoring_desc']!,
                      Icons.speed,
                      selections['Performance Monitoring']!,
                    ),
                    _buildOptionCard(
                      translations['optimize_app_usage']!,
                      translations['optimize_app_usage_desc']!,
                      Icons.settings_applications,
                      selections['Optimize App Usage']!,
                    ),
                    _buildOptionCard(
                      translations['manage_background']!,
                      translations['manage_background_desc']!,
                      Icons.trending_up,
                      selections['Manage Background Processes']!,
                    ),
                  ],
                ),
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 16),
                    child: SizedBox(
                      width: 200,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isOptimizing ? null : startOptimization,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Text(
                          isOptimizing ? translations['optimizing']! : translations['start_optimization']!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: isEnglish ? 0.5 : 0,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.visible,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRamIndicator(String label, String value, Color color) {
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
            Text(
              label,
              style: TextStyle(fontSize: 12),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }


  Future<void> fetchUnusedApps() async {
    print("⭐ Fetching unused apps...");
    setState(() {
      isLoadingApps = true;
    });

    try {
      // Call native method to get unused apps
      final List<dynamic> unusedAppsData = await platform.invokeMethod('getUnusedApps');

      print("⭐ Received ${unusedAppsData.length} unused apps from platform");

      // If empty list returned, might need permission
      if (unusedAppsData.isEmpty) {
        bool hasPermission = await platform.invokeMethod('checkUsagePermission');
        if (!hasPermission) {
          // Ask for permission
          await platform.invokeMethod('openUsageSettings');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please grant usage access permission')),
          );
        }
        _setDefaultUnusedApps();
        return;
      }

      setState(() {
        // Clear the existing list
        unusedApps.clear();

        // Convert the returned data to UnusedAppInfo objects
        for (var app in unusedAppsData) {
          final String name = app['appName'] ?? app['name'] ?? 'Unknown App';
          final String packageName = app['packageName'] ?? '';
          final int ramUsage = app['ramUsage'] ?? 100_000_000; // Default 100MB if not provided
          final DateTime lastUsed = app['lastUsed'] != null ?
          DateTime.fromMillisecondsSinceEpoch(app['lastUsed']) :
          DateTime.now().subtract(Duration(days: 7)); // Default 7 days ago
          final int daysSinceUsed = app['daysSinceUsed'] ??
              DateTime.now().difference(lastUsed).inDays;

          unusedApps.add(UnusedAppInfo(
            name: name,
            packageName: packageName,
            ramUsage: formatMemorySize(ramUsage),
            lastUsed: lastUsed,
            daysSinceUsed: daysSinceUsed,
            isSelected: true,
          ));
        }
      });
    } catch (e) {
      print("❌ Error fetching unused apps: $e");
      // Fallback to example apps if fetch fails
      _setDefaultUnusedApps();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Using demo data: $e')),
        );
      }
    } finally {
      setState(() {
        isLoadingApps = false;
      });
    }
  }

  void _setDefaultUnusedApps() {
    final now = DateTime.now();

    unusedApps = [
      UnusedAppInfo(
        name: 'Old Game',
        packageName: 'com.example.oldgame',
        ramUsage: '120 MB',
        lastUsed: now.subtract(Duration(days: 30)),
        daysSinceUsed: 30,
        isSelected: true,
      ),
      UnusedAppInfo(
        name: 'Abandoned Chat',
        packageName: 'com.example.oldchat',
        ramUsage: '85 MB',
        lastUsed: now.subtract(Duration(days: 45)),
        daysSinceUsed: 45,
        isSelected: true,
      ),
      UnusedAppInfo(
        name: 'Rarely Used Editor',
        packageName: 'com.example.rarelyused',
        ramUsage: '150 MB',
        lastUsed: now.subtract(Duration(days: 14)),
        daysSinceUsed: 14,
        isSelected: true,
      ),
    ];
  }


  Widget _buildOptionCard(String key, String description, IconData icon, bool isSelected) {
    // Get the language provider using Provider
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    // Translate the title based on key
    String title;
    switch (key) {
      case 'Clean RAM':
        title = isEnglish ? 'Clean RAM' : 'تنظيف ذاكرة الوصول العشوائي';
        break;
      case 'Performance Monitoring':
        title = isEnglish ? 'Performance Monitoring' : 'مراقبة الأداء';
        break;
      case 'Optimize App Usage':
        title = isEnglish ? 'Optimize App Usage' : 'تحسين استخدام التطبيق';
        break;
      case 'Manage Background Processes':
        title = isEnglish ? 'Manage Background Processes' : 'إدارة العمليات الخلفية';
        break;
      default:
        title = key;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFC),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 32),
            SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            SizedBox(height: 4),
            Expanded(
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 10, // Smaller font size
                  color: Colors.grey[600],
                  height: 1.2, // Tighter line height
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.visible, // Allow text to be visible
              ),
            ),
          ],
        ),
      ),
    );
  }


}

class AppRamUsage {
  final String name;
  final String ramUsage;
  final IconData? icon;
  bool isSelected;
  final String packageName;

  AppRamUsage({
    required this.name,
    required this.ramUsage,
    this.icon,
    required this.isSelected,
    required this.packageName,
  });

  factory AppRamUsage.fromMap(Map<String, dynamic> map) {
    return AppRamUsage(
      name: map['name'] as String,
      ramUsage: formatMemorySize(map['ramUsage'] as int),
      icon: Icons.android,
      packageName: map['packageName'] as String,
      isSelected: true,
    );
  }
}



String formatMemorySize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else {
    // For GB values, apply special rounding rules
    double gbValue = bytes / (1024 * 1024 * 1024);

    // Round to nearest GB for display purposes
    if (gbValue > 7.0 && gbValue < 8.5) {
      return '8 GB';  // Display 8 GB for values close to 8 (like 7.5)
    } else if (gbValue > 15.0 && gbValue < 16.5) {
      return '16 GB'; // Display 16 GB for values close to 16
    } else if (gbValue > 31.0 && gbValue < 33.0) {
      return '32 GB'; // Display 32 GB for values close to 32
    } else if (gbValue > 63.0 && gbValue < 66.0) {
      return '64 GB'; // Display 64 GB for values close to 64
    } else {
      // For other values, round to 1 decimal place
      return '${gbValue.toStringAsFixed(1)} GB';
    }
  }
}
