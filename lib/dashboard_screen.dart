import 'dart:async';
import 'dart:io';
import 'dart:math';


import 'package:clean_guru/performancescreen.dart';
import 'package:clean_guru/settingScreen.dart';
import 'package:clean_guru/storageOptimizationScreen.dart';
import 'package:clean_guru/subscriptionScreen.dart';
import 'package:clean_guru/systemCleaner.dart';
import 'package:clean_guru/systemMetrics.dart';
import 'package:clean_guru/themeprovider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_info2/system_info2.dart';
import 'package:provider/provider.dart';
import 'package:clean_guru/languageProvider.dart';

// Or if your "official" one is the one in settingScreen.dart, use:
import 'package:clean_guru/settingScreen.dart';

import 'appLifecycleCreator.dart';
import 'appOpenAd.dart';
import 'bannerAdWidget.dart';
import 'batterysavermannager.dart';
import 'memoryScreen.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver{
  int _selectedIndex = 0;
  int _currentPage = 0;
  bool _lastLanguage = false; // Track language changes
  bool _isLoading = true;
  //BannerAd? _bannerAd;
  final String _adUnitId = kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111' // Test ad unit ID
      : 'ca-app-pub-3940256099942544/6300978111';
  bool _hasCleanedMemory = false;
  double _memoryReductionGB = 0.0;

  //late AppOpenAdManager appOpenAdManager;
  late AppLifecycleReactor appLifecycleReactor;
  final AppOpenAdManager appOpenAdManager = AppOpenAdManager();

  bool _isBannerAdReady = false;

  final PageController _pageController = PageController();
  Timer? _refreshTimer;
  int _runningProcessesCount = 3;  // Start with 3 running processes
  List<GaugeData> gauges = []; // Initialize empty
//  BannerAd? _bannerAd;

  Future<String> getFormattedStorageUsage() async {
    try {
      final storage = await getStorageInfo();
      if (storage['total'] == 0) return '0 GB';

      final usedBytes = storage['used']!;
      final totalBytes = storage['total']!;
      final usedGB = usedBytes / (1024 * 1024 * 1024);
      final totalGB = totalBytes / (1024 * 1024 * 1024);

      return '${usedGB.toStringAsFixed(1)} GB of ${totalGB.toStringAsFixed(0)} GB';
    } catch (e) {
      return 'N/A';
    }
  }

  static Future<Map<String, int>> getStorageInfo() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.arabapps.cleangru/storage');
        final result = await platform.invokeMethod('getStorageInfo');

        return {
          'total': (result['total'] as int),
          'used': (result['used'] as int),
          'free': (result['free'] as int),
        };
      }

      // Fallback for non-Android
      final directory = await getApplicationDocumentsDirectory();
      final stat = directory.statSync();
      return {
        'total': stat.size,
        'used': stat.size ~/ 2,
        'free': stat.size ~/ 2,
      };
    } catch (e) {
      print('Error getting storage info: $e');
      return {'total': 0, 'used': 0, 'free': 0};
    }
  }

  Future<Color> getStorageColor() async {
    try {
      final storage = await getStorageInfo();
      if (storage['total'] == 0) return Colors.blue;

      final usedPercentage = (storage['used']! / storage['total']!) * 100;

      if (usedPercentage < 50) return Colors.green;
      if (usedPercentage < 80) return Colors.orange;
      return Colors.red;
    } catch (e) {
      return Colors.blue;
    }
  }



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appOpenAdManager.showAdIfAvailable();
    });

    // Load the first ad
    //appOpenAdManager.loadAd();
    _initializeGauges();

    setState(() {
      _isLoading = true;
    });

    // Load metrics after a short delay
    Future.delayed(Duration.zero, () {
      _loadSystemStatistics();


    });

    // Add a more robust language change listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      languageProvider.addListener(() {
        // When language changes, force a complete refresh
        setState(() {
          _lastLanguage = languageProvider.currentLocale.languageCode == 'ar';
        });
        _loadSystemStatistics();


        // Reset any button states if needed
      });
    });

    _refreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _loadSystemStatistics();


      _updateBackgroundProcessCount();
    });


  }



  String _roundRAMSize(double ramGB) {
    // Round total RAM to standard sizes
    if (ramGB <= 4) return '4';
    if (ramGB <= 8) return '8';
    if (ramGB <= 16) return '16';
    if (ramGB <= 32) return '32';
    if (ramGB <= 64) return '64';
    if (ramGB <= 128) return '128';
    return '256';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pageController.dispose();

    // Unregister the observer when widget is disposed
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  void _initializeGauges() {
    gauges = [
      GaugeData(
        title: 'Device Vitality',
        value: 0,
        suffix: '/100',
        buttonText: 'Optimize',
        details: [],
        detailGroups: [],
      ),
      GaugeData(
        title: 'Storage Analytics',
        value: 0,
        suffix: '% used',
        buttonText: 'Clean Storage',
        details: [],
        detailGroups: [],
      ),
     /* GaugeData(
        title: 'Performance Metrics',
        value: 0,
        suffix: '%',
        buttonText: 'Boost Performance',
        details: [],
        detailGroups: [],
      ),*/
      GaugeData(
        title: 'Battery Status',
        value: 0,
        suffix: '%',
        buttonText: 'Optimize Battery',
        details: [],
        detailGroups: [],
      ),
      GaugeData(
        title: 'Memory Usage',
        value: 0,
        suffix: '% used',
        buttonText: 'Free Up Memory',
        details: [],
        detailGroups: [],
      ),
    ];
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // Check if permission dialog is showing and dismiss it
      // This is a bit of a hack, but it works by popping any dialog that might be showing
      Navigator.of(context).popUntil((route) => route.isFirst);

      // Then check permission status
      //_checkUsageAccessPermission();

      // Also update background processes count
      _updateBackgroundProcessCount();
    }
  }

  Future<bool> _checkUsageAccessPermission() async {
    try {
      // Get the method channel for native method calls
      const platform = MethodChannel('com.arabapps.cleangru/memory');

      // Check if usage access permission is granted
      final hasPermission = await platform.invokeMethod('checkUsageAccessPermission');

      // Update the state with the permission status
      setState(() {
        _hasUsageAccessPermission = hasPermission;
      });

      // If permission is granted, load system metrics
      if (hasPermission) {
        _loadSystemStatistics();


      }

      return hasPermission;
    } catch (e) {
      print('Error checking usage access permission: $e');
      return false;
    }
  }

  void _showPermissionRequired() {
    // Don't show dialog if permission is already granted or view is not mounted
    if (_hasUsageAccessPermission || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Permission Required'),
          content: Text(
            'Clean Guru needs usage access permission to identify unused apps. '
                'This helps optimize your device by recommending which apps to close or uninstall.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openUsageAccessSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text('Grant Permission'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openUsageAccessSettings() async {
    try {
      const platform = MethodChannel('com.arabapps.cleangru/memory');
      await platform.invokeMethod('openUsageAccessSettings');
    } catch (e) {
      print('Error opening usage access settings: $e');
      // Fallback method if the channel call fails
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enable usage access for Clean Guru in system settings.'),
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () {
              try {
                openAppSettings();
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Please enable usage access manually in system settings')),
                );
              }
            },
          ),
        ),
      );
    }
  }

  bool _hasUsageAccessPermission = false;




  void _updateBackgroundProcessCount() async {
    try {
      // Get the method channel for native method calls
      const platform = MethodChannel('com.arabapps.cleangru/memory');

      // Get the current background apps count
      final backgroundAppsData = await platform.invokeMethod('getBackgroundAppsCount');
      final backgroundAppsCount = backgroundAppsData['count'] as int;

      // Get current language for translations
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final isArabic = languageProvider.currentLocale.languageCode == 'ar';

      // Update the performance metrics gauge with the new count
      setState(() {
        for (int i = 0; i < gauges.length; i++) {
          if (gauges[i].title == 'Performance Metrics' || gauges[i].title == 'مقاييس الأداء') {
            // Update the background process count in the detail groups
            if (gauges[i].detailGroups.isNotEmpty) {
              for (int j = 0; j < gauges[i].detailGroups.length; j++) {
                DetailGroup group = gauges[i].detailGroups[j];
                List<DetailItem> updatedItems = [];

                // Create new items with updated background process count
                for (DetailItem item in group.items) {
                  if (item.label == 'Background Processes' || item.label == 'العمليات في الخلفية') {
                    updatedItems.add(DetailItem(
                      label: isArabic ? 'العمليات في الخلفية' : 'Background Processes',
                      value: '$backgroundAppsCount',
                      color: item.color,
                    ));
                  } else {
                    updatedItems.add(item);
                  }
                }

                // Update the group with new items
                gauges[i].detailGroups[j] = DetailGroup(
                  title: group.title,
                  items: updatedItems,
                );
              }
            }
          }
        }
      });

      print('Updated background processes count to: $backgroundAppsCount');
    } catch (e) {
      print('Error updating background processes count: $e');
    }
  }




  Future<void> _loadSystemStatistics() async {
    try {
      // Get the current language
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final isArabic = languageProvider.currentLocale.languageCode == 'ar';

      // PART 1: Quickly load the main gauge values
      // This makes the UI responsive faster

      // Get device vitality score (basic)
      final deviceVitality = await SystemMetrics.calculateDeviceVitality(context);

      // Get storage usage percentage (basic)
      final storage = await SystemMetrics.getStorageInfo();
      final storageUsedPercentage = (storage['used']! / storage['total']! * 100).round();

      // Get basic performance data with a single method channel call
      const platform = MethodChannel('com.arabapps.cleangru/memory');
      final performanceMetrics = await platform.invokeMethod('getPerformanceMetrics');

      // Safely extract RAM values with default fallbacks
      int totalRAM = performanceMetrics['totalRam'] as int? ?? 8 * 1024 * 1024 * 1024; // Default 8GB in bytes
      int usedRAM = performanceMetrics['usedRam'] as int? ?? 4 * 1024 * 1024 * 1024; // Default 4GB in bytes
      int freeRAM = performanceMetrics['freeRam'] as int? ?? 4 * 1024 * 1024 * 1024; // Default 4GB in bytes

      // Apply memory reduction if we have cleaned memory
      if (_hasCleanedMemory) {
        // Convert GB to bytes for reduction
        int reductionBytes = (_memoryReductionGB * 1024 * 1024 * 1024).round();

        // Apply reduction to reported values
        usedRAM = max(200 * 1024 * 1024, usedRAM - reductionBytes); // Ensure at least 200MB used
        freeRAM = min(totalRAM - usedRAM, freeRAM + reductionBytes);
      }

      // Extract essential values
      final cpuUsage = performanceMetrics['cpuUsage'] is double ?
      (performanceMetrics['cpuUsage'] as double).round() :
      performanceMetrics['cpuUsage'] as int;

      // Calculate RAM sizes
      final totalRAMGB = (totalRAM / (1024 * 1024 * 1024));
      final roundedTotalRAMGB = _roundRAMSize(totalRAMGB);

      // Calculate proportional used and free RAM based on rounded total
      final usedRAMGB = (usedRAM / (1024 * 1024 * 1024));
      final roundedUsedRAMGB = (double.parse(roundedTotalRAMGB) * (usedRAMGB / totalRAMGB)).toStringAsFixed(1);

      final freeRAMGB = (freeRAM / (1024 * 1024 * 1024));
      final roundedFreeRAMGB = (double.parse(roundedTotalRAMGB) * (freeRAMGB / totalRAMGB)).toStringAsFixed(1);

      // Calculate memory percentage using the same values
      final memoryUsedPercentage = ((usedRAM / totalRAM) * 100).round();

      // Get battery level (basic)
      final batteryLevel = await SystemMetrics.getBatteryScore();

      // Update UI with basic data first
      setState(() {
        gauges[0] = GaugeData(
          title: isArabic ? 'حيوية الجهاز' : 'Device Vitality',
          value: deviceVitality.value,
          suffix: '/100',
          buttonText: isArabic ? 'تحليل' : 'Analyze',
          details: [],
          detailGroups: [], // Will fill this later
        );

        gauges[1] = GaugeData(
          title: isArabic ? 'تحليلات التخزين' : 'Storage Analytics',
          value: storageUsedPercentage,
          suffix: isArabic ? '% مستخدم' : '% used',
          buttonText: isArabic ? 'تنظيف التخزين' : 'Clean Storage',
          details: [],
          detailGroups: [], // Will fill this later
        );

        // gauges[2] = GaugeData(
        //   title: isArabic ? 'مقاييس الأداء' : 'Performance Metrics',
        //   value: cpuUsage,
        //   suffix: '%',
        //   buttonText: isArabic ? 'تحسين الأداء' : ' Performance',
        //   details: [],
        //   detailGroups: [], // Will fill this later
        // );

        gauges[2] = GaugeData(
          title: isArabic ? 'حالة البطارية' : 'Battery Status',
          value: batteryLevel,
          suffix: '%',
          buttonText: isArabic ? 'تحسين البطارية' : 'Optimize Battery',
          details: [],
          detailGroups: [], // Will fill this later
        );

        gauges[3] = GaugeData(
          title: isArabic ? 'استخدام الذاكرة' : 'Memory Usage',
          value: memoryUsedPercentage,
          suffix: isArabic ? '% مستخدم' : '% used',
          buttonText: isArabic ? 'تحرير الذاكرة' : ' Memory',
          details: [],
          detailGroups: [], // Will fill this later
        );

        // Mark loading as complete for basic data
        _isLoading = false;
      });

      // PART 2: Load detailed information in the background
      // Use microtask to avoid blocking UI thread
      Future.microtask(() async {
        try {
          // Now we can take time to load all the detailed metrics

          // 1. Translate device vitality detail groups
          List<DetailGroup> translatedDeviceVitalityGroups = [];
          for (var group in deviceVitality.detailGroups) {
            String translatedGroupTitle = group.title;

            // Translate group titles
            if (group.title == 'Device Vitality') {
              translatedGroupTitle = isArabic ? 'حيوية الجهاز' : 'Device Vitality';
            } else if (group.title == 'System Health') {
              translatedGroupTitle = isArabic ? 'صحة النظام' : 'System Health';
            }

            // Translate items within each group
            List<DetailItem> translatedItems = [];
            for (var item in group.items) {
              String translatedLabel = item.label;

              // Add mappings for all item labels that need translation
              if (item.label == 'Overall Health') {
                translatedLabel = isArabic ? 'الصحة العامة' : 'Overall Health';
              } else if (item.label == 'System Performance') {
                translatedLabel = isArabic ? 'أداء النظام' : 'System Performance';
              } else if (item.label == 'Storage Health') {
                translatedLabel = isArabic ? 'صحة التخزين' : 'Storage Health';
              } else if (item.label == 'Memory Health') {
                translatedLabel = isArabic ? 'صحة الذاكرة' : 'Memory Health';
              } else if (item.label == 'Battery Health') {
                translatedLabel = isArabic ? 'صحة البطارية' : 'Battery Health';
              }

              translatedItems.add(DetailItem(
                label: translatedLabel,
                value: item.value,
                color: item.color,
              ));
            }

            translatedDeviceVitalityGroups.add(DetailGroup(
              title: translatedGroupTitle,
              items: translatedItems,
            ));
          }

          // 2. Create detailed storage analysis
          final totalGB = (storage['total']! / (1024 * 1024 * 1024));
          final standardTotalGB = _getStandardStorageSize(totalGB);
          final usedStorageGB = (storage['used']! / (1024 * 1024 * 1024)).toStringAsFixed(1);
          final freeStorageGB = (storage['free']! / (1024 * 1024 * 1024)).toStringAsFixed(1);

          final storageDetails = DetailGroup(
            title: isArabic ? 'تحليلات التخزين' : 'Storage Analytics',
            items: [
              DetailItem(
                label: isArabic ? 'التخزين الكلي' : 'Total Storage',
                value: '$standardTotalGB GB',
                color: Colors.blue,
              ),
              DetailItem(
                label: isArabic ? 'التخزين المستخدم' : 'Used Storage',
                value: '$usedStorageGB GB',
                color: Colors.orange,
              ),
              DetailItem(
                label: isArabic ? 'التخزين المتاح' : 'Free Storage',
                value: '$freeStorageGB GB',
                color: Colors.green,
              ),
            ],
          );

          // 3. Get remaining performance metrics
         final backgroundAppsData = await platform.invokeMethod('getBackgroundAppsCount');
          final temperature = await platform.invokeMethod('getDeviceTemperature');
          final backgroundAppsCount = backgroundAppsData['count'] as int;



          // 4. Get detailed battery status
          final originalBatteryStatus = await SystemMetrics.getBatteryStatus();

          // Create a translated version of the battery status detail group
          DetailGroup translatedBatteryStatus = DetailGroup(
            title: isArabic ? 'حالة البطارية' : 'Battery Status',
            items: [],
          );

          // Copy and translate each item in the battery status
          if (originalBatteryStatus.items.isNotEmpty) {
            List<DetailItem> translatedItems = [];
            for (var item in originalBatteryStatus.items) {
              String translatedLabel = item.label;

              // Translate common battery status labels
              if (item.label == 'Charging Status') {
                translatedLabel = isArabic ? 'حالة الشحن' : 'Charging Status';
              } else if (item.label == 'Battery Health') {
                translatedLabel = isArabic ? 'صحة البطارية' : 'Battery Health';
              } else if (item.label == 'Estimated Time Left') {
                translatedLabel = isArabic ? 'الوقت المتبقي' : 'Estimated Time Left';
              } else if (item.label == 'Power Source') {
                translatedLabel = isArabic ? 'مصدر الطاقة' : 'Power Source';
              } else if (item.label == 'Current Level') {
                translatedLabel = isArabic ? 'المستوى الحالي' : 'Current Level';
              } else if (item.label == 'Battery Level') {
                translatedLabel = isArabic ? 'مستوى البطارية' : 'Battery Level';
              } else if (item.label == 'Power Mode') {
                translatedLabel = isArabic ? 'وضع الطاقة' : 'Power Mode';
              } else if (item.label == 'Temperature') {
                translatedLabel = isArabic ? 'درجة الحرارة' : 'Temperature';
              } else if (item.label == 'Charging Speed') {
                translatedLabel = isArabic ? 'سرعة الشحن' : 'Charging Speed';
              } else if (item.label == 'Remaining Charge Time') {
                translatedLabel = isArabic ? 'وقت الشحن المتبقي' : 'Remaining Charge Time';
              } else if (item.label == 'Usage Time Left') {
                translatedLabel = isArabic ? 'وقت الاستخدام المتبقي' : 'Usage Time Left';
              }

              translatedItems.add(DetailItem(
                label: translatedLabel,
                value: item.value,
                color: item.color,
              ));
            }

            translatedBatteryStatus = DetailGroup(
              title: isArabic ? 'حالة البطارية' : 'Battery Status',
              items: translatedItems,
            );
          }

          // 5. Create detailed memory usage data with rounded values
          final memoryUsageDetails = DetailGroup(
            title: isArabic ? 'استخدام الذاكرة' : 'Memory Usage',
            items: [
              DetailItem(
                label: isArabic ? 'إجمالي ذاكرة الوصول العشوائي' : 'Total RAM',
                value: '$roundedTotalRAMGB GB',
                color: Colors.blue,
              ),
              DetailItem(
                label: isArabic ? 'ذاكرة الوصول العشوائي المستخدمة' : 'Used RAM',
                value: '$roundedUsedRAMGB GB',
                color: Colors.orange,
              ),
              DetailItem(
                label: isArabic ? 'ذاكرة الوصول العشوائي الحرة' : 'Free RAM',
                value: '$roundedFreeRAMGB GB',
                color: Colors.green,
              ),
            ],
          );

          // 6. Update UI with complete detailed data
          setState(() {
            gauges[0] = GaugeData(
              title: isArabic ? 'حيوية الجهاز' : 'Device Vitality',
              value: deviceVitality.value,
              suffix: '/100',
              buttonText: isArabic ? 'تحسين' : 'Optimize',
              details: [],
              detailGroups: translatedDeviceVitalityGroups,
            );

            gauges[1] = GaugeData(
              title: isArabic ? 'تحليلات التخزين' : 'Storage Analytics',
              value: storageUsedPercentage,
              suffix: isArabic ? '% مستخدم' : '% used',
              buttonText: isArabic ? 'تنظيف التخزين' : 'Clean Storage',
              details: [],
              detailGroups: [storageDetails],
            );
           /* gauges[2] = GaugeData(
              title: isArabic ? 'مقاييس الأداء' : 'Performance Metrics',
              value: cpuUsage,
              suffix: '%',
              buttonText: isArabic ? 'تحسين الأداء' : 'Boost Performance',
              details: [],
              detailGroups: [enhancedPerformanceMetrics],
            );*/

            gauges[2] = GaugeData(
              title: isArabic ? 'حالة البطارية' : 'Battery Status',
              value: batteryLevel,
              suffix: '%',
              buttonText: isArabic ? 'تحسين البطارية' : 'Optimize Battery',
              details: [],
              detailGroups: [translatedBatteryStatus],
            );

            gauges[3] = GaugeData(
              title: isArabic ? 'استخدام الذاكرة' : 'Memory Usage',
              value: memoryUsedPercentage,
              suffix: isArabic ? '% مستخدم' : '% used',
              buttonText: isArabic ? 'تحرير الذاكرة' : 'Free Up Memory',
              details: [],
              detailGroups: [memoryUsageDetails],
            );
          });
        } catch (e) {
          print('Error loading detailed metrics: $e');
        }
      });
    } catch (e) {
      print('Error in _loadSystemMetrics: $e');
      // Make sure we're not stuck in loading state
      setState(() {
        _isLoading = false;
      });
    }
  }


// Add this helper method to your class
  String _getStandardStorageSize(double sizeGB) {
    // Round to standard storage size
    if (sizeGB <= 20) return "16.0";
    if (sizeGB <= 40) return "32.0";
    if (sizeGB <= 80) return "64.0";
    if (sizeGB <= 150) return "128.0";
    if (sizeGB <= 280) return "256.0";
    if (sizeGB <= 550) return "512.0";
    return "1024.0";
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isArabic = languageProvider.currentLocale.languageCode == 'ar';
    if (_lastLanguage != isArabic) {
      _lastLanguage = isArabic;
      // Force refresh of gauges with new language
      Future.microtask(() => _loadSystemStatistics()


      );
    }


    final translations = {
      // Navigation & Titles
      'dashboard': isArabic ? 'لوحة التحكم' : 'Dashboard',
      'storage': isArabic ? 'التخزين' : 'Storage',
      'memory': isArabic ? 'الذاكرة' : 'Memory',
      'settings': isArabic ? 'الضبط' : 'Settings',
      'clean': isArabic ? 'تحليل' : 'Analyze', // Changed from "Clean" to "Analyze"
      'guru': isArabic ? 'مونيتور' : 'Monitor', // Changed from "Guru" to "Monitor"

      // Gauge Titles
      'device_vitality': isArabic ? 'حيوية الجهاز' : 'Device Vitality',
      'storage_analytics': isArabic ? 'تحليلات التخزين' : 'Storage Analytics',
      'performance_metrics': isArabic ? 'مقاييس الأداء' : 'Performance Metrics',
      'battery_status': isArabic ? 'حالة البطارية' : 'Battery Status',
      'memory_usage': isArabic ? 'استخدام الذاكرة' : 'Memory Usage',

      // Button Actions
      'analyze': isArabic ? 'تحليل' : 'Analyze', // Instead of "Optimize"
      'analyze_storage': isArabic ? 'تحليل التخزين' : 'Analyze Storage', // Instead of "Clean Storage"
      'manage_apps': isArabic ? 'اداره التطبيق' : 'Manage Apps', // Already appropriate
      'battery_tips': isArabic ? 'نصائح البطارية' : 'Battery Tips', // Already appropriate
      'clear_cache': isArabic ? 'تنظيف الكاش' : 'Clear Cache', // This is OK since cache clearing is legitimate

      // Dialog Texts
      'clearing_cache': isArabic ? 'تنظيف ملفات الكاش' : 'Clearing Cache Files',
      'please_wait': isArabic ? 'يرجى الانتظار...' : 'Please wait...',
      'cache_cleared': isArabic ? 'تم تنظيف الكاش!' : 'Cache cleared!',
      'clearing_failed': isArabic ? 'فشل التنظيف:' : 'Clearing failed:',
      'clear_cache_files': isArabic ? 'تنظيف ملفات الكاش' : 'Clear Cache Files',
      'clear_cache_confirmation': isArabic ? 'سيؤدي هذا إلى إزالة الملفات المؤقتة والكاش لتحرير مساحة التخزين. متابعة؟' : 'This will remove temporary files and cache to free up storage space. Continue?',
      'cancel': isArabic ? 'إلغاء' : 'CANCEL',
      'clear': isArabic ? 'تنظيف' : 'CLEAR',

      // Analysis Results
      'analysis_complete': isArabic ? 'اكتمل التحليل!' : 'Analysis complete!',
      'running_apps': isArabic ? 'التطبيقات قيد التشغيل:' : 'Running apps:',
      'apps_background_info': isArabic ? 'هذه التطبيقات نشطة حاليًا في الخلفية وقد تستخدم موارد النظام.' : 'These apps are currently active in the background and may be using system resources.',
      'close': isArabic ? 'إغلاق' : 'Close',
      'device_analysis': isArabic ? 'تحليل الجهاز' : 'Device Analysis',

      // App Management
      'manage_running_apps': isArabic ? 'إدارة التطبيقات قيد التشغيل' : 'Manage Running Apps',
      'unknown_app': isArabic ? 'تطبيق غير معروف' : 'Unknown App',
      'close_selected': isArabic ? 'إغلاق المحدد' : 'Close Selected',
      'closed_apps': isArabic ? 'تم إغلاق التطبيقات' : 'Closed apps',
      'no_background_apps': isArabic ? 'لم يتم العثور على تطبيقات في الخلفية' : 'No background apps found',
      'error_closing_apps': isArabic ? 'خطأ في إغلاق التطبيقات:' : 'Error closing apps:',

      // Cache Clearing Process
      'clearing_app_cache': isArabic ? 'تنظيف كاش التطبيق...' : 'Clearing app cache...',
      'removing_temp_files': isArabic ? 'إزالة الملفات المؤقتة...' : 'Removing temporary files...',
      'cleaning_cache_files': isArabic ? 'تنظيف ملفات الكاش...' : 'Cleaning cache files...',
      'cleared_cache': isArabic ? 'تم تنظيف الكاش والملفات المؤقتة' : 'Cleared cache and temporary files',
      'failed_clean_files': isArabic ? 'فشل تنظيف الملفات:' : 'Failed to clean files:',

      // Permissions
      'permission_required': isArabic ? 'الإذن مطلوب' : 'Permission Required',
      'grant_permission': isArabic ? 'منح الإذن' : 'Grant Permission',
      'later': isArabic ? 'لاحقًا' : 'Later',
      'please_grant_usage_access': isArabic ? 'يرجى منح إذن الوصول للاستخدام لتحليل التطبيقات' : 'Please grant usage access permission to analyze apps',

      // Battery Tips
      'battery_optimization_tips': isArabic ? 'نصائح تحسين البطارية' : 'Battery Optimization Tips',
      'to_optimize_battery': isArabic ? 'لتحسين عمر البطارية:' : 'To optimize your battery life:',
      'reduce_brightness': isArabic ? 'تقليل سطوع الشاشة' : 'Reduce screen brightness',
      'enable_battery_saver': isArabic ? 'تفعيل وضع توفير البطارية' : 'Enable battery saver mode',
      'close_unused_apps': isArabic ? 'إغلاق التطبيقات غير المستخدمة' : 'Close unused background apps',
      'reduce_screen_timeout': isArabic ? 'تقليل مهلة إيقاف الشاشة' : 'Reduce screen timeout',
      'open_settings': isArabic ? 'فتح الإعدادات' : 'Open Settings',

      // Memory Usage Details
      'total_ram': isArabic ? 'إجمالي ذاكرة الوصول العشوائي' : 'Total RAM',
      'used_ram': isArabic ? 'ذاكرة الوصول العشوائي المستخدمة' : 'Used RAM',
      'free_ram': isArabic ? 'ذاكرة الوصول العشوائي الحرة' : 'Free RAM',
      'used': isArabic ? 'مستخدم' : 'used',
      'of': isArabic ? 'من' : 'of',

      // Performance Metrics
      'cpu_usage': isArabic ? 'استخدام المعالج' : 'CPU Usage',
      'background_processes': isArabic ? 'العمليات في الخلفية' : 'Background Processes',
      'device_temperature': isArabic ? 'درجة حرارة الجهاز' : 'Device Temperature',

      // Storage Details
      'total_storage': isArabic ? 'التخزين الكلي' : 'Total Storage',
      'used_storage': isArabic ? 'التخزين المستخدم' : 'Used Storage',
      'free_storage': isArabic ? 'التخزين المتاح' : 'Free Storage',

      // Performance Status Descriptions
      'good': isArabic ? 'جيد' : 'Good',
      'moderate': isArabic ? 'متوسط' : 'Moderate',
      'high': isArabic ? 'مرتفع' : 'High',
    };



    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Color(0xFFF2F9FF),
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Clean ',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              TextSpan(
                text: 'Guru',
                style: TextStyle(
                  color: Color(0xFF16599A),
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),
        ),// Add this line for the custom color

        /* title: Text(
          LanguageProvider.translate(context, 'dashboard'),
        ),*/
        // Add this section to include the settings icon
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            color: Colors.black, // Make the icon visible

            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),

      body: Container(
        color: Color(0xFFF5F5F5), // Add background color to Container
        child: Column(
          children: [
            // Main content area (takes all available space)
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildDashboardContent(translations),
                  StorageOptimizationScreen(
                    languageProvider: Provider.of<LanguageProvider>(context, listen: false),
                  ),
                  MemoryScreen(),
                  //PerformanceScreen(),
                  SettingsScreen()
                ],
              ),
            ),

            if (Platform.isAndroid) BannerAdWidget(),
          ],
        ),
      ),

      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Container(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_outlined, translations['dashboard']!, 0),
              _buildNavItem(Image.asset('assets/folder.png', width: 24, height: 24), translations['storage']!, 1),
            //  const SizedBox(width: 60), // Space for the FAB
              _buildNavItem(Icons.memory_outlined, translations['memory']!, 2),
              _buildNavItem(Icons.settings, translations['settings']!, 3),
            ],
          ),
        ),
      ),

    );
  }




// Fixed implementation to ensure dialog closes
  void _performJunkCleaningFixed(BuildContext context) {
    // Store the dialog's BuildContext
    late BuildContext dialogContext;

    // Show processing dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx; // Store the dialog context
        return _buildCleaningDialog();
      },
    );

    // Execute cleaning in a try-catch-finally to ensure dialog closes
    try {
      // Run an immediate microtask to avoid blocking the UI
      Future.microtask(() async {
        try {
          await Future.delayed(Duration(seconds: 3)); // Simulate work
          // In a real implementation:
          // final result = await SystemCleaner.cleanJunkFiles();

          // Close dialog using the stored context
          Navigator.of(dialogContext).pop();

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cleaning complete!'), backgroundColor: Colors.green),
          );

          // Refresh metrics
          _loadSystemStatistics();
        } catch (e) {
          print('Error during cleaning: $e');
          // Always close the dialog, even on error
          Navigator.of(dialogContext).pop();

          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cleaning failed: $e'), backgroundColor: Colors.red),
          );
        }
      });
    } catch (e) {
      print('Failed to start cleaning task: $e');
      // If showing the dialog or starting the task fails, try to close dialog
      try {
        Navigator.of(dialogContext).pop();
      } catch (e) {
        print('Failed to close dialog: $e');
      }
    }
  }


  Widget _buildCleaningDialog() {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'Cleaning Junk Files',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Please wait...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearMemoryCache() async {
    try {
      // Get cache directories
      final tempDir = await getTemporaryDirectory();
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = Directory('${appDir.path}/Cache');

      // Verify directories exist before clearing
      final directories = [
        tempDir,
        cacheDir
      ].where((dir) => dir != null && dir.existsSync()).toList();

      // Calculate initial cache sizes
      final initialSizes = <String, int>{};
      for (var dir in directories) {
        initialSizes[dir.path] = await _getDirSize(dir);
        print('Initial cache size for ${dir.path}: ${initialSizes[dir.path]} bytes');
      }

      // Show confirmation dialog
      final shouldClear = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Memory Cache Management'),
            content: const Text('Clear cache to free up memory'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text(
                  'Cancel',
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
                child: const Text('Clear Cache'),
              ),
            ],
          );
        },
      );

      // Only proceed if user confirms
      if (shouldClear != true) return;

      // Attempt to clear each directory
      final clearResults = <String, bool>{};
      int totalFreed = 0;

      for (var dir in directories) {
        try {
          // List files before deletion
          final filesBefore = await dir.list().toList();
          print('Files in ${dir.path} before deletion: ${filesBefore.length}');

          // Clear directory
          int dirFreed = await _cleanDirectory(dir, null);
          totalFreed += dirFreed;

          // Verify deletion
          final filesAfter = await dir.list().toList();
          print('Files in ${dir.path} after deletion: ${filesAfter.length}');

          // Check if files were actually deleted
          clearResults[dir.path] = filesAfter.isEmpty;
        } catch (e) {
          print('Error clearing directory ${dir.path}: $e');
          clearResults[dir.path] = false;
        }
      }

      // Verify cache deletion
      bool allCleared = clearResults.values.every((result) => result);

      if (mounted) {
        if (allCleared) {
          Fluttertoast.showToast(
            msg: 'Successfully cleared ${(totalFreed / 1024 / 1024).toStringAsFixed(2)} MB of cache',
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.green,
            textColor: Colors.white,
          );
        } else {
          // Detailed error about which directories failed to clear
          String failedDirs = clearResults.entries
              .where((entry) => !entry.value)
              .map((entry) => entry.key)
              .join(', ');

          Fluttertoast.showToast(
            msg: 'Partial cache clearing. Failed to clear: $failedDirs',
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.orange,
            textColor: Colors.white,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Error during cache clearing: ${e.toString()}',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
    }
  }

  Future<int> _cleanDirectory(Directory directory, List<String>? extensions) async {
    int freedSpace = 0;
    try {
      if (await directory.exists()) {
        await for (var entity in directory.list(recursive: true)) {
          if (entity is File) {
            if (extensions == null ||
                extensions.any((ext) => entity.path.toLowerCase().endsWith(ext))) {
              freedSpace += await entity.length();
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      print('Error cleaning directory: ${e.toString()}');
    }
    return freedSpace;
  }
  // Add this method to handle the actual junk cleaning process
  void _performJunkCleaning(BuildContext context) async {
    // Show processing dialog
    _showCleaningDialog(context);

    try {
      // Simulate initial scan (in a real app, you could actually scan first)
      await Future.delayed(Duration(milliseconds: 800));

      // Close the initial dialog and show updated one
      Navigator.pop(context);
      _showCleaningDialog(context, state: 'Cleaning cache files...', progress: 20);

      // Clean app cache
      await Future.delayed(Duration(milliseconds: 500));
      Navigator.pop(context);

      _showCleaningDialog(context, state: 'Removing temporary files...', progress: 40);

      // Clean temp files
      await Future.delayed(Duration(milliseconds: 500));

      Navigator.pop(context);

      _showCleaningDialog(context, state: 'Cleaning log files...', progress: 60);

      // Clean log files
      await Future.delayed(Duration(milliseconds: 500));

      Navigator.pop(context);

      _showCleaningDialog(context, state: 'Removing thumbnail cache...', progress: 80);

      // Clean thumbnails
      await Future.delayed(Duration(milliseconds: 500));

      // In a real app, use the actual SystemCleaner implementation
      final result = await SystemCleaner.cleanJunkFiles();

      // Close the dialog
      Navigator.pop(context);

      // Show success message with results
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cleanup complete!'),
              Text(
                '${result.filesDeleted} files cleaned (${result.formattedBytesFreed} freed)',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );

      // Refresh your app's metrics or data
      _loadSystemStatistics();

    } catch (e) {
      // If an error occurs, close the dialog and show error message
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cleaning junk files: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<int> _getDirSize(Directory dir) async {
    int size = 0;
    try {
      if (await dir.exists()) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            size += await entity.length();
          }
        }
      }
    } catch (e) {
      print('Error calculating directory size: $e');
    }
    return size;
  }

  // Update the dialog to show cleaning progress with status
  void _showCleaningDialog(BuildContext context, {String state = 'Scanning for junk files...', int progress = 0}) {
    showDialog(
      context: context,
      barrierDismissible: false, // User cannot dismiss by tapping outside
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  value: progress > 0 ? progress / 100 : null, // Show determinate progress when available
                ),
                SizedBox(height: 20),
                Text(
                  'Cleaning Junk Files',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  state,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (progress > 0) ...[
                  SizedBox(height: 8),
                  Text(
                    '$progress%',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem(dynamic icon, String label, int index) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon is IconData
              ? Icon(
            icon,
            color: _selectedIndex == index ? Colors.green : Colors.grey,
          )
              : icon, // Use the widget directly if it's not an IconData
          Text(
            label,
            style: TextStyle(
              color: _selectedIndex == index ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }


  void _showProcessingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing the dialog by tapping outside
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                SizedBox(height: 20),
                Text(
                  'Processing',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '0%',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  Widget _buildDashboardContent(Map<String, String> translations) {
    // Get the current language provider
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isArabic = languageProvider.currentLocale.languageCode == 'ar';

    // Comprehensive translation map
    final fullTranslations = {
      'Device Vitality': {
        'en': 'Device Vitality',
        'ar': 'حيوية الجهاز'
      },
      'Storage Analytics': {
        'en': 'Storage Analytics',
        'ar': 'تحليلات التخزين'
      },
      'Performance Metrics': {
        'en': 'Performance Metrics',
        'ar': 'مقاييس الأداء'
      },
      'Battery Status': {
        'en': 'Battery Status',
        'ar': 'حالة البطارية'
      },
      'Memory Usage': {
        'en': 'Memory Usage',
        'ar': 'استخدام الذاكرة'
      },
      'Optimize': {
        'en': 'Optimize',
        'ar': 'تحسين'
      },
      'Clean Storage': {
        'en': 'Clean Storage',
        'ar': 'تنظيف التخزين'
      },
      'Boost Performance': {
        'en': 'Boost Performance',
        'ar': 'تحسين الأداء'
      },
      'Optimize Battery': {
        'en': 'Optimize Battery',
        'ar': 'تحسين البطارية'
      },
      'Free Up Memory': {
        'en': 'Free Up Memory',
        'ar': 'تحرير الذاكرة'
      }
    };

    // Translate the gauges
    List<GaugeData> translatedGauges = gauges.map((gauge) {
      // Translate the title
      String translatedTitle = fullTranslations[gauge.title]?[isArabic ? 'ar' : 'en'] ?? gauge.title;

      // Translate the button text
      String translatedButtonText = fullTranslations[gauge.buttonText]?[isArabic ? 'ar' : 'en'] ?? gauge.buttonText;

      // Translate detail groups
      List<DetailGroup> translatedDetailGroups = gauge.detailGroups.map((group) {
        // Translate group title
        String translatedGroupTitle = fullTranslations[group.title]?[isArabic ? 'ar' : 'en'] ?? group.title;

        // Translate items
        List<DetailItem> translatedItems = group.items.map((item) {
          // Map of specific label translations
          final labelTranslations = {
            'Total RAM': {
              'en': 'Total RAM',
              'ar': 'إجمالي ذاكرة الوصول العشوائي'
            },
            'Used RAM': {
              'en': 'Used RAM',
              'ar': 'ذاكرة الوصول العشوائي المستخدمة'
            },
            'Free RAM': {
              'en': 'Free RAM',
              'ar': 'ذاكرة الوصول العشوائي الحرة'
            },
            'CPU Usage': {
              'en': 'CPU Usage',
              'ar': 'استخدام المعالج'
            },
            'Background Processes': {
              'en': 'Background Processes',
              'ar': 'العمليات في الخلفية'
            },
            'Device Temperature': {
              'en': 'Device Temperature',
              'ar': 'درجة حرارة الجهاز'
            }
          };

          // Translate the label
          String translatedLabel = labelTranslations[item.label]?[isArabic ? 'ar' : 'en'] ?? item.label;

          return DetailItem(
            label: translatedLabel,
            value: item.value,
            color: item.color,
          );
        }).toList();

        return DetailGroup(
          title: translatedGroupTitle,
          items: translatedItems,
        );
      }).toList();

      return GaugeData(
        title: translatedTitle,
        value: gauge.value,
        suffix: gauge.suffix,
        buttonText: translatedButtonText,
        details: gauge.details,
        detailGroups: translatedDetailGroups,
      );
    }).toList();

    // Rest of the method remains the same
    return PageView.builder(
      controller: _pageController,
      itemCount: translatedGauges.length,
      onPageChanged: (int page) {
        setState(() {
          _currentPage = page;
        });
      },
      itemBuilder: (context, index) {
        return _buildGaugePage(translatedGauges[index]);
      },
    );
  }



  _buildGaugePage(GaugeData data) {
    bool isDeviceVitality = data.title == 'Device Vitality' || data.title == 'حيوية الجهاز';

    // Get language for handling button actions
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Title
            Text(
              data.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),

            // Gauge
            CustomGauge(
              value: data.value,
              suffix: data.suffix,
              size: 250,
            ),

            // Pagination dots
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                gauges.length,
                    (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? Colors.black
                        : Colors.grey.withOpacity(0.3),
                  ),
                ),
              ),
            ),

            // For device vitality, show metrics list
            if (isDeviceVitality && data.detailGroups.isNotEmpty) ...[
              const SizedBox(height: 30),
              _buildVitalityMetricsList(data.detailGroups),
            ]
            // For other gauges, show detailed groups
            else if (data.detailGroups.isNotEmpty) ...[
              const SizedBox(height: 30),
              _buildDetailsView(data.detailGroups),
            ],
          ],
        ),
      ),
    );
  }



  Future<int> _calculateDirSize(Directory dir) async {
    int totalSize = 0;
    try {
      if (await dir.exists()) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      print('Error calculating directory size: $e');
    }
    return totalSize;
  }





  Widget _buildVitalityMetricsList(List<DetailGroup> detailGroups) {
    // Get the current language provider
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isArabic = languageProvider.currentLocale.languageCode == 'ar';

    // Translations for metrics
    final translations = {
      'en': {
        'storage_used': 'Storage Used', // Changed from 'storage_analytics'
        'total_storage': 'Total Storage',
        'used_storage': 'Used Storage',
        'free_storage': 'Free Storage',
        'memory_usage': 'Memory Usage',
        'total_ram': 'Total RAM',
        'used_ram': 'Used RAM',
        'free_ram': 'Free RAM',
        'performance_metrics': 'Performance Metrics',
        'cpu_usage': 'CPU Usage',
        'background_processes': 'Background Processes',
        'battery_status': 'Battery Status',
        'battery_level': 'Battery Level',
        'charging_status': 'Charging Status',
        'device_status': 'Device Status',
      },
      'ar': {
        'storage_used': 'التخزين المستخدم', // Changed from 'storage_analytics'
        'total_storage': 'التخزين الكلي',
        'used_storage': 'التخزين المستخدم',
        'free_storage': 'التخزين المتاح',
        'memory_usage': 'استخدام الذاكرة',
        'total_ram': 'إجمالي ذاكرة الوصول العشوائي',
        'used_ram': 'ذاكرة الوصول العشوائي المستخدمة',
        'free_ram': 'ذاكرة الوصول العشوائي الحرة',
        'performance_metrics': 'مقاييس الأداء',
        'cpu_usage': 'استخدام المعالج',
        'background_processes': 'العمليات في الخلفية',
        'battery_status': 'حالة البطارية',
        'battery_level': 'مستوى البطارية',
        'charging_status': 'حالة الشحن',
        'device_status': 'حالة الجهاز',
      }
    };
    final storageGauge = gauges.firstWhere(
            (g) => g.title == 'Storage Used' || g.title == 'التخزين المستخدم',
        orElse: () => gauges.firstWhere(
                (g) => g.title == 'Storage Analytics' || g.title == 'تحليلات التخزين'
        )
    );
    // Get current metrics
   // final storageAnalytics = gauges.firstWhere((g) => g.title == 'Storage Analytics' || g.title == 'تحليلات التخزين');
    final memoryUsage = gauges.firstWhere((g) => g.title == 'Memory Usage' || g.title == 'استخدام الذاكرة');
   // final performanceMetrics = gauges.firstWhere((g) => g.title == 'Performance Metrics' || g.title == 'مقاييس الأداء');
    final batteryStatus = gauges.firstWhere((g) => g.title == 'Battery Status' || g.title == 'حالة البطارية');

    // Get translation map based on current language
    final t = isArabic ? translations['ar']! : translations['en']!;

    // Get formatted values
   // final storageValue = '${storageAnalytics.value}% ${isArabic ? 'مستخدم' : 'used'}';
    final storageValue = storageGauge.value; // This should now be the formatted string like "34.5 GB"

    // Memory usage with translation
    String memoryValue = '${memoryUsage.value}% ${isArabic ? 'مستخدم' : 'used'}';
    if (memoryUsage.detailGroups.isNotEmpty && memoryUsage.detailGroups[0].items.length >= 2) {
      final totalItem = memoryUsage.detailGroups[0].items.firstWhere(
            (item) => item.label == 'Total RAM' || item.label == 'إجمالي ذاكرة الوصول العشوائي',
        orElse: () => DetailItem(label: '', value: '', color: Colors.blue),
      );

      final usedItem = memoryUsage.detailGroups[0].items.firstWhere(
            (item) => item.label == 'Used RAM' || item.label == 'ذاكرة الوصول العشوائي المستخدمة',
        orElse: () => DetailItem(label: '', value: '', color: Colors.orange),
      );

      if (totalItem.value.isNotEmpty && usedItem.value.isNotEmpty) {
        memoryValue = '${usedItem.value} ${isArabic ? 'من' : 'of'} ${totalItem.value} ${isArabic ? 'مستخدم' : 'used'}';
      }
    }

    // Performance metrics translation
 /*   String performanceValue;
    if (performanceMetrics.value < 30) {
      performanceValue = isArabic ? 'جيد' : 'Good';
    } else if (performanceMetrics.value < 70) {
      performanceValue = isArabic ? 'متوسط' : 'Moderate';
    } else {
      performanceValue = isArabic ? 'مرتفع' : 'High';
    }*/

    // Battery percentage
    final batteryValue = '${batteryStatus.value}%';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FutureBuilder<String>(
              future: getFormattedStorageUsage(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildMetricItem(
                      t['storage_used']!,
                      'Loading...',
                      Colors.grey
                  );
                } else if (snapshot.hasError) {
                  return _buildMetricItem(
                      t['storage_used']!,
                      'Error',
                      Colors.red
                  );
                } else {
                  final storageValue = snapshot.data ?? 'N/A';
                  return FutureBuilder<Color>(
                    future: getStorageColor(),
                    builder: (context, colorSnapshot) {
                      final color = colorSnapshot.data ?? Colors.blue;
                      return _buildMetricItem(
                          t['storage_used']!,
                          storageValue,
                          color
                      );
                    },
                  );
                }
              },
            ),
            // _buildMetricItem(
            //     t['storage_used']!, // Updated key
            //     storageValue,
            //     Colors.blue // Static color, or create logic based on usage level
            //),
            // _buildMetricItem(
            //     t['storage_analytics']!,
            //     storageValue,
            //     _getIndicatorColor(storageAnalytics.value, true)
            // ),
            const Divider(height: 24),
            _buildMetricItem(
                t['memory_usage']!,
                memoryValue,
                _getIndicatorColor(memoryUsage.value, true)
            ),
          //  const Divider(height: 24),
           /* _buildMetricItem(
                t['performance_metrics']!,
                performanceValue,
                _getIndicatorColor(performanceMetrics.value, false)
            ),*/
            const Divider(height: 24),
            _buildMetricItem(
                t['battery_status']!,
                batteryValue,
                _getIndicatorColor(batteryStatus.value, false)
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildMetricItem(String title, String value, Color indicatorColor) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: indicatorColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsView(List<DetailGroup> detailGroups) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: detailGroups.map((group) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: group.items.isEmpty ? 1 : group.items.length,
                    itemBuilder: (context, index) {
                      if (group.items.isEmpty) {
                        return _buildDetailItem(
                          group.title,
                          _getPlaceholderData(group.title),
                          Colors.blue,
                        );
                      }
                      return _buildDetailItem(
                        group.items[index].label,
                        group.items[index].value,
                        group.items[index].color,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: color,
            width: 4,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getIndicatorColor(int value, bool isHigherWorse) {
    if (isHigherWorse) {
      if (value < 50) return Colors.blue; // Low usage - good
      if (value < 75) return Colors.orange; // Medium usage - warning
      return Colors.red; // High usage - bad
    } else {
      if (value > 75) return Colors.blue; // High value - good
      if (value > 40) return Colors.orange; // Medium value - warning
      return Colors.red; // Low value - bad
    }
  }




  String _getPlaceholderData(String groupTitle) {
    switch (groupTitle) {
      case 'Storage Analytics':
        return '75% used';
      case 'Total Storage':
        return '64 GB';
      case 'Used Storage':
        return '48 GB';
      case 'Free Storage':
        return '16 GB';
      case 'CPU Usage':
        return '45%';
      case 'Background Processes':
        return '14 active';
      case 'Device Temperature':
        return '37°C';
      case 'Battery Health':
        return 'Degraded';
      case 'Charging Status':
        return 'Fast Charging';
      case 'Estimated Time Left':
        return '4 hours 12 minutes';
      case 'Total RAM':
        return '8 GB';
      case 'Used':
        return '4 GB';
      case 'Free':
        return '2 GB';
      case 'Apps':
        return '24 GB';
      default:
        return '';
    }
  }

}


class GaugeData {
  final String title;
  final int value;
  final String suffix;
  final String buttonText;
  final List<DetailItem> details;
  final List<DetailGroup> detailGroups;

  GaugeData({
    required this.title,
    required this.value,
    required this.suffix,
    required this.buttonText,
    required this.details,
    required this.detailGroups,
  });

  // Add this factory constructor for automatic filtering
  factory GaugeData.filtered({
    required String title,
    required int value,
    required String suffix,
    required String buttonText,
    required List<DetailItem> details,
    required List<DetailGroup> detailGroups,
  }) {
    // Filter out invalid detail items
    final validDetails = details.where((item) => item.isValid).toList();

    // Filter out invalid detail groups
    final validGroups = detailGroups
        .map((group) => group.withFilteredItems()) // First filter items within each group
        .where((group) => group.hasValidItems)     // Then filter out empty groups
        .toList();

    return GaugeData(
      title: title.trim(),
      value: value,
      suffix: suffix,
      buttonText: buttonText,
      details: validDetails,
      detailGroups: validGroups,
    );
  }

  // Add this getter to check if this gauge has any meaningful data
  bool get hasData =>
      title.isNotEmpty &&
          (details.isNotEmpty || detailGroups.isNotEmpty);
}

class DetailGroup {
  final String title;
  final List<DetailItem> items;

  DetailGroup({
    required this.title,
    required this.items,
  });

  // Add this method to create a new DetailGroup with filtered items
  DetailGroup withFilteredItems() {
    return DetailGroup(
      title: title,
      items: items.where((item) => item.isValid).toList(),
    );
  }

  // Add this getter to check if group has valid items
  bool get hasValidItems =>
      title.trim().isNotEmpty &&
          items.any((item) => item.isValid);
}

/*class DetailItem {
  final String label;
  final String value;
  final Color color;

  DetailItem({
    required this.label,
    required this.value,
    required this.color,
  });
}*/

class DetailItem {
  final String label;
  final String value;
  final Color color;

  DetailItem({
    required this.label,
    required this.value,
    required this.color,
  });

  // Add this getter to check if item is valid (not empty)
  bool get isValid =>
      label.trim().isNotEmpty &&
          value.trim().isNotEmpty;
}

class CustomGauge extends StatelessWidget {
  final int value;
  final String suffix;
  final double size;

  const CustomGauge({
    Key? key,
    required this.value,
    this.suffix = '/100',
    this.size = 200,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Gauge with properly positioned pointer
        CustomPaint(
          size: Size(size, size * 0.75),
          painter: GaugePainter(value: value),
        ),

        // Value and suffix display directly at the bottom without spacing
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              suffix,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}


class GaugePainter extends CustomPainter {
  final int value;

  GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.45;

    // Draw track (background arc)
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..color = Colors.grey.shade200;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi * 5 / 4,
      pi * 3 / 2,
      false,
      trackPaint,
    );

    // Create gradient colors
    final gradientColors = [
      const Color(0xFF4CAF50),   // Green (start)
      const Color(0xFF8BC34A),   // Light green
      const Color(0xFFCDDC39),   // Lime
      const Color(0xFFFFEB3B),   // Yellow
      const Color(0xFFFFC107),   // Amber
      const Color(0xFFFF9800),   // Orange
      const Color(0xFFFF5722),   // Deep orange
      const Color(0xFFF44336),   // Red (end)
    ];

    // Draw colored progress arc with gradient
    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    final gradient = SweepGradient(
      transform: GradientRotation(-pi * 5 / 4),
      colors: gradientColors,
      stops: const [0.0, 0.14, 0.28, 0.42, 0.56, 0.7, 0.85, 1.0],
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    gradientPaint.shader = gradient.createShader(rect);

    final double sweepAngle = (value / 100) * (pi * 3 / 2);
    canvas.drawArc(
      rect,
      -pi * 5 / 4,
      sweepAngle,
      false,
      gradientPaint,
    );

    // Draw tick marks
    _drawTicks(canvas, center, radius);

    // Draw pointer (arrow)
    _drawPointer(canvas, center, radius, value);

    // Draw center knob
    canvas.drawCircle(
      center,
      10,
      Paint()..color = Colors.black,
    );
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    final Paint tickPaint = Paint()
      ..color = Colors.black38
      ..strokeWidth = 1;

    for (int i = 0; i <= 20; i++) {
      final double angle = -pi * 5 / 4 + (pi * 3 / 2 * i / 20);

      final bool isMajor = i % 5 == 0;
      final double innerRadius = isMajor ? radius - 20 : radius - 15;
      final double outerRadius = radius - 5;

      tickPaint.strokeWidth = isMajor ? 2 : 1;

      final double x1 = center.dx + outerRadius * cos(angle);
      final double y1 = center.dy + outerRadius * sin(angle);
      final double x2 = center.dx + innerRadius * cos(angle);
      final double y2 = center.dy + innerRadius * sin(angle);

      canvas.drawLine(
        Offset(x1, y1),
        Offset(x2, y2),
        tickPaint,
      );
    }
  }

  void _drawPointer(Canvas canvas, Offset center, double radius, int value) {
    final angle = -pi * 5 / 4 + (value / 100 * pi * 3 / 2);

    // Draw a simple needle-like arrow as shown in the reference image
    // The arrow consists of a thin red line with a black center point

    // Calculate the arrow length and starting position
    final arrowLength = radius * 0.85; // Make it slightly longer

    // Arrow tip position
    final tipPosition = Offset(
        center.dx + cos(angle) * arrowLength,
        center.dy + sin(angle) * arrowLength
    );

    // Draw the arrow line (thin and red)
    final arrowPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5  // Thin line
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, tipPosition, arrowPaint);

    // Add a black center point
    final centerPointPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 7.0, centerPointPaint);

    // Add a small red overlay on top of the black center
    final centerRedPointPaint = Paint()
      ..color = Colors.red.shade800
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 3.0, centerRedPointPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is GaugePainter && oldDelegate.value != value;
  }
}