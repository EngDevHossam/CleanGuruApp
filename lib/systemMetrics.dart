import 'dart:io';
import 'package:clean_guru/storageHelper.dart';
import 'package:clean_guru/traanslation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:system_info2/system_info2.dart';
import 'package:provider/provider.dart';
import 'dashboard_screen.dart';
import 'languageProvider.dart';



class SystemMetrics {
  static final Battery _battery = Battery();
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();


  static Future<int> getStorageScore() async {
    final storage = await getStorageInfo();
    if (storage['total'] == 0) return 0;
    final usedPercentage = (storage['used']! / storage['total']!) * 100;
    return (100 - usedPercentage).round();
  }
  // Storage Analytics
  static Future<GaugeData> calculateDeviceVitality(BuildContext context) async {
    try {
      // Get the current language from LanguageProvider
      final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
      final currentLang = languageProvider.currentLocale.languageCode;

      // Get metrics with platform checks
      final storageScore = await getStorageScore();
      final memoryScore = await getMemoryScore();
      final performanceScore = await getPerformanceScore();
      final batteryScore = await getBatteryScore();

      // Calculate overall vitality score
      final vitalityScore = (storageScore * 0.3 +
          memoryScore * 0.3 +
          performanceScore * 0.2 +
          batteryScore * 0.2).round();

      // Create a summary group with dynamic translation
      final summary = DetailGroup(
        title: Translations.translate('system_health_overview', lang: currentLang),
        items: [
          DetailItem(
            label: Translations.translate('storage_used', lang: currentLang), // Change translation key
            value: await getUsedStorageFormatted(), // Use the new function
            color: Colors.blue, // You can keep a static color or create logic based on usage
          ),
          // DetailItem(
          //   label: Translations.translate('storage_analytics', lang: currentLang),
          //   value: '$storageScore%',
          //   color: storageScore > 60 ? Colors.green :
          //   storageScore > 30 ? Colors.orange : Colors.red,
          // ),
          DetailItem(
            label: Translations.translate('memory_usage', lang: currentLang),
            value: '$memoryScore%',
            color: memoryScore > 60 ? Colors.green :
            memoryScore > 30 ? Colors.orange : Colors.red,
          ),
          DetailItem(
            label: Translations.translate('performance_metrics', lang: currentLang),
            value: '$performanceScore%',
            color: performanceScore > 60 ? Colors.green :
            performanceScore > 30 ? Colors.orange : Colors.red,
          ),
          DetailItem(
            label: Translations.translate('battery_status', lang: currentLang),
            value: '$batteryScore%',
            color: batteryScore > 60 ? Colors.green :
            batteryScore > 30 ? Colors.orange : Colors.red,
          ),
        ],
      );

      return GaugeData(
        title: Translations.translate('device_vitality', lang: currentLang),
        value: vitalityScore,
        suffix: '/100',
        buttonText: Translations.translate('optimize', lang: currentLang),
        details: [],
        detailGroups: [summary],
      );
    } catch (e) {
      print('Error in calculateDeviceVitality: $e');
      // Return default values if there's an error
      return GaugeData(
        title: 'Device Vitality',
        value: 75, // Default reasonable value
        suffix: '/100',
        buttonText: 'Optimize',
        details: [],
        detailGroups: [
          DetailGroup(
            title: 'System Health',
            items: [
              DetailItem(
                label: 'Overall Health',
                value: 'Good',
                color: Colors.green,
              ),
            ],
          ),
        ],
      );
    }
  }


  static Future<int> getBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (e) {
      print('Error getting battery level: $e');
      return 72; // Default value
    }
  }

  static Future<String> getBatteryHealth() async {
    try {
      // This is a simplified implementation
      final batteryLevel = await _battery.batteryLevel;
      if (batteryLevel > 80) return 'Good';
      if (batteryLevel > 50) return 'Moderate';
      return 'Degraded';
    } catch (e) {
      print('Error getting battery health: $e');
      return 'Degraded'; // Default value
    }
  }

  static Future<String> getChargingStatus() async {
    try {
      final batteryState = await _battery.batteryState;
      switch (batteryState) {
        case BatteryState.charging:
          return 'Fast Charging';
        case BatteryState.full:
          return 'Fully Charged';
        case BatteryState.discharging:
          return 'Discharging';
        default:
          return 'Unknown';
      }
    } catch (e) {
      print('Error getting charging status: $e');
      return 'Fast Charging'; // Default value
    }
  }

  static Future<String> getEstimatedTimeLeft() async {
    // This is a mock implementation
    try {
      final batteryLevel = await _battery.batteryLevel;
      if (batteryLevel > 80) return '6 hours 30 minutes';
      if (batteryLevel > 50) return '4 hours 12 minutes';
      return '2 hours 45 minutes';
    } catch (e) {
      print('Error getting estimated time left: $e');
      return '4 hours 12 minutes'; // Default value
    }
  }

  static Future<int> getBackgroundProcessCount() async {
    // Mock implementation
    try {
      // In a real implementation, this would use platform-specific methods
      return 14; // Default background process count
    } catch (e) {
      print('Error getting background process count: $e');
      return 14;
    }
  }


  static Future<DetailGroup> getMemoryUsage() async {
    if (Platform.isIOS) {
      try {
        const platform = MethodChannel('com.arabapps.cleangru/memory');
        final performanceMetrics = await platform.invokeMethod('getPerformanceMetrics');

        final totalRAM = performanceMetrics['totalRam'] as int;
        final usedRAM = performanceMetrics['usedRam'] as int;
        final freeRAM = performanceMetrics['freeRam'] as int;
        final usedPercentage = ((usedRAM / totalRAM) * 100).round();

        return DetailGroup(
          title: 'Memory Usage',
          items: [
            DetailItem(
              label: 'Total RAM',
              value: formatSize(totalRAM),
              color: Colors.blue,
            ),
            DetailItem(
              label: 'Used RAM',
              value: '${formatSize(usedRAM)} (${usedPercentage}%)',
              color: usedPercentage > 90 ? Colors.red :
              usedPercentage > 70 ? Colors.orange : Colors.green,
            ),
            DetailItem(
              label: 'Free RAM',
              value: formatSize(freeRAM),
              color: Colors.green,
            ),
          ],
        );
      } catch (e) {
        print('Error getting memory usage on iOS: $e');
        // Return default values for iOS
        return DetailGroup(
          title: 'Memory Usage',
          items: [
            DetailItem(
              label: 'Total RAM',
              value: '4.0 GB',
              color: Colors.blue,
            ),
            DetailItem(
              label: 'Used RAM',
              value: '2.0 GB (50%)',
              color: Colors.orange,
            ),
            DetailItem(
              label: 'Free RAM',
              value: '2.0 GB',
              color: Colors.green,
            ),
          ],
        );
      }
    } else {
      // Original Android implementation
      final totalRAM = SysInfo.getTotalPhysicalMemory();
      final freeRAM = SysInfo.getFreePhysicalMemory();
      final usedRAM = totalRAM - freeRAM;
      final usedPercentage = ((usedRAM / totalRAM) * 100).round();

      return DetailGroup(
        title: 'Memory Usage',
        items: [
          DetailItem(
            label: 'Total RAM',
            value: formatSize(totalRAM),
            color: Colors.blue,
          ),
          DetailItem(
            label: 'Used RAM',
            value: '${formatSize(usedRAM)} (${usedPercentage}%)',
            color: usedPercentage > 90 ? Colors.red :
            usedPercentage > 70 ? Colors.orange : Colors.green,
          ),
          DetailItem(
            label: 'Free RAM',
            value: formatSize(freeRAM),
            color: Colors.green,
          ),
        ],
      );
    }
  }

  static Future<Map<String, int>> getDiskSpaceInfo() async {
    try {
      // If you're using the method_channel approach to communicate with native code
      final methodChannel = MethodChannel('com.arabapps.cleangru/storage');
      final result = await methodChannel.invokeMethod('getStorageInfo');

      return {
        'total': result['total'] as int,
        'used': result['used'] as int,
        'free': result['free'] as int,
      };
    } catch (e) {
      print('Error getting disk space info: $e');

      // Return some default values if there's an error
      return {
        'total': 64 * 1024 * 1024 * 1024, // 64 GB
        'used': 48 * 1024 * 1024 * 1024,  // 48 GB
        'free': 16 * 1024 * 1024 * 1024,  // 16 GB
      };
    }
  }


  static Future<int> getCPUUsage() async {
    try {
      if (Platform.isAndroid) {
        final file = File('/proc/stat');
        if (await file.exists()) {
          final String contents = await file.readAsString();
          final List<String> lines = contents.split('\n');
          final String cpuLine = lines.firstWhere(
                (line) => line.startsWith('cpu '),
            orElse: () => '',
          );

          if (cpuLine.isNotEmpty) {
            final List<String> values = cpuLine.split(' ')
                .where((value) => value.isNotEmpty)
                .skip(1)
                .toList();

            if (values.length >= 4) {
              final int user = int.parse(values[0]);
              final int nice = int.parse(values[1]);
              final int system = int.parse(values[2]);
              final int idle = int.parse(values[3]);

              final int total = user + nice + system + idle;
              final int active = user + nice + system;

              return ((active / total) * 100).round();
            }
          }
        }

        final result = await Process.run('top', ['-n', '1', '-b']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final regex = RegExp(r'(\d+\.?\d*)%\s+cpu');
          final match = regex.firstMatch(output);
          if (match != null) {
            return double.parse(match.group(1)!).round();
          }
        }
      }

      final processCount = await getRunningProcessCount();
      final cores = Platform.numberOfProcessors;
      return ((processCount / (cores * 10)) * 100).round().clamp(0, 100);

    } catch (e) {
      print('Error getting CPU usage: $e');
    }
    return 50;
  }

  // Add this to your SystemMetrics class
  static Future<int> terminateBackgroundProcesses() async {
    try {
      final methodChannel = MethodChannel('com.arabapps.cleangru/memory');
      final result = await methodChannel.invokeMethod('terminateBackgroundProcesses');
      return result as int;
    } catch (e) {
      print('Error terminating background processes: $e');
      // Return a default value if there's an error
      return 14; // Default to 14 processes
    }
  }


  static Future<DetailGroup> getBatteryStatus() async {
    final batteryLevel = await _battery.batteryLevel;
    final batteryState = await _battery.batteryState;
    final isLowPower = await _battery.isInBatterySaveMode;

    String chargingStatus;
    switch (batteryState) {
      case BatteryState.charging:
        chargingStatus = 'Charging';
        break;
      case BatteryState.full:
        chargingStatus = 'Fully Charged';
        break;
      case BatteryState.discharging:
        chargingStatus = 'Discharging';
        break;
      default:
        chargingStatus = 'Unknown';
    }

    return DetailGroup(
      title: 'Battery Status',
      items: [
        DetailItem(
          label: 'Battery Level',
          value: '$batteryLevel%',
          color: getBatteryColor(batteryLevel),
        ),
        DetailItem(
          label: 'Charging Status',
          value: chargingStatus,
          color: batteryState == BatteryState.charging ? Colors.green :
          batteryState == BatteryState.full ? Colors.blue : Colors.orange,
        ),
        DetailItem(
          label: 'Power Mode',
          value: isLowPower ? 'Power Saving' : 'Normal',
          color: isLowPower ? Colors.orange : Colors.green,
        ),
      ],
    );
  }

  static Future<String> getUsedStorageFormatted() async {
    final storage = await getStorageInfo();
    if (storage['total'] == 0) return '0 GB';

    final usedBytes = storage['used']!;
    final usedGB = usedBytes / (1024 * 1024 * 1024); // Convert to GB

    return '${usedGB.toStringAsFixed(1)} GB';
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



  static Future<List<Map<String, dynamic>>> getRunningProcesses() async {
    try {
      const MethodChannel channel = MethodChannel('com.arabapps.cleangru/memory');
      final result = await channel.invokeMethod('getRunningApps'); // Use getRunningApps instead of getRunningProcesses
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      print('Error getting running processes: $e');
      return [];
    }
  }


  static Future<Map<String, dynamic>> getBackgroundAppsCount() async {
    try {
      const MethodChannel channel = MethodChannel('com.arabapps.cleangru/memory');
      final result = await channel.invokeMethod('getBackgroundAppsCount');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      print('Error getting background apps count: $e');
      return {
        'count': 2,
        'apps': ['Default App 1', 'Default App 2']
      };
    }
  }


  static Future<DetailGroup> getPerformanceMetrics() async {
    int cpuUsage = await getCPUUsage();

    // Hardcoded background apps count
    const int backgroundAppsCount = 3;  // Or any other number you prefer

    return DetailGroup(
      title: 'Performance Metrics',
      items: [
        DetailItem(
          label: 'CPU Usage',
          value: '$cpuUsage%',
          color: cpuUsage > 90 ? Colors.red :
          cpuUsage > 70 ? Colors.orange : Colors.green,
        ),
        DetailItem(
          label: 'Background Apps',
          value: backgroundAppsCount.toString(),
          color: Colors.blue,
        ),
        DetailItem(
          label: 'CPU Cores',
          value: Platform.numberOfProcessors.toString(),
          color: Colors.blue,
        ),
      ],
    );
  }


  static Future<int> getMemoryScore() async {
    if (Platform.isIOS) {
      // Use method channel on iOS
      try {
        const platform = MethodChannel('com.arabapps.cleangru/memory');
        final performanceMetrics = await platform.invokeMethod('getPerformanceMetrics');
        final totalRAM = performanceMetrics['totalRam'] as int;
        final usedRAM = performanceMetrics['usedRam'] as int;
        final usedPercentage = (usedRAM / totalRAM) * 100;
        return (100 - usedPercentage).round();
      } catch (e) {
        print('Error getting memory score on iOS: $e');
        return 50; // Default value for iOS
      }
    } else {
      // Use SysInfo on Android
      final totalRAM = SysInfo.getTotalPhysicalMemory();
      if (totalRAM == 0) return 0;
      final usedRAM = totalRAM - SysInfo.getFreePhysicalMemory();
      final usedPercentage = (usedRAM / totalRAM) * 100;
      return (100 - usedPercentage).round();
    }
  }

  static Future<int> getPerformanceScore() async {
    final cpuUsage = await getCPUUsage();
    return (100 - cpuUsage).clamp(0, 100);
  }


  static Future<int> getBatteryScore() async {
    return await _battery.batteryLevel;
  }


  static Future<int> getRunningProcessCount() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 23) {
          final result = await Process.run('ps', []);
          if (result.exitCode == 0) {
            return result.stdout.toString().split('\n').length - 1;
          }
        }
      }
    } catch (e) {
      print('Error getting process count: $e');
    }
    return 0;
  }


  static String formatSize(int bytes) {
    const int kb = 1024;
    const int mb = kb * 1024;
    const int gb = mb * 1024;

    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    }
    if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }


  static Color getBatteryColor(int level) {
    if (level > 60) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }

}