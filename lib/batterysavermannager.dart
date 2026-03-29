

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

class BatterySaverManager {
  final Battery _battery = Battery();

  // Method to check if battery saver is currently enabled
  Future<bool> isBatterySaverEnabled() async {
    try {
      // Use platform channel to check battery saver status
      const platform = MethodChannel('com.example.clean_guru/battery');
      final isEnabled = await platform.invokeMethod('isBatterySaverEnabled');
      return isEnabled ?? false;
    } catch (e) {
      print('Error checking battery saver status: $e');
      return false;
    }

  }

  // Comprehensive battery optimization method
  Future<void> optimizeBattery(BuildContext context) async {
    try {
      // Get current battery level
      final batteryLevel = await _battery.batteryLevel;
      final batteryStatus = await _battery.batteryState;

      // Use platform channel to enable battery saver
      const platform = MethodChannel('com.example.clean_guru/battery');

      // Toggle battery saver mode
      final result = await platform.invokeMethod('toggleBatterySaverMode');

      // Additional optimizations
      await _performAdditionalOptimizations();

      // Provide user feedback
      _showBatteryOptimizationFeedback(context, batteryLevel, result);
    } catch (e) {
      print('Battery optimization error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to optimize battery'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Additional battery-saving techniques
  Future<void> _performAdditionalOptimizations() async {
    try {
      // Reduce screen brightness
      final screenBrightness = ScreenBrightness();
      await screenBrightness.setScreenBrightness(0.3); // 30% brightness

      // Close background processes
      const platform = MethodChannel('com.example.clean_guru/memory');
      await platform.invokeMethod('terminateBackgroundProcesses');

      // Disable unnecessary sensors and connections
      await _disableUnecessaryConnections();
    } catch (e) {
      print('Additional optimization error: $e');
    }
  }

  // Disable unnecessary connections and sensors
  Future<void> _disableUnecessaryConnections() async {
    try {
      const platform = MethodChannel('com.example.clean_guru/system');
      await platform.invokeMethod('disableBluetoooth');
      await platform.invokeMethod('disableWiFi');
      await platform.invokeMethod('disableLocationServices');
    } catch (e) {
      print('Connection disabling error: $e');
    }
  }

  // Provide detailed feedback about battery optimization
  void _showBatteryOptimizationFeedback(
      BuildContext context,
      int batteryLevel,
      dynamic optimizationResult
      ) {
    // Translate the optimization result
    String optimizationMessage = _translateOptimizationResult(optimizationResult);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Battery Optimization Applied'),
            Text('Current Battery: $batteryLevel%'),
            Text(optimizationMessage),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 4),
      ),
    );
  }

  // Translate optimization result to user-friendly message
  String _translateOptimizationResult(dynamic result) {
    if (result is Map) {
      // Example of processing a detailed result
      final processesKilled = result['processesKilled'] ?? 0;
      final memoryFreed = result['memoryFreed'] ?? 0;

      return 'Processes Killed: $processesKilled\n'
          'Memory Freed: ${(memoryFreed / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    return result?.toString() ?? 'Optimization completed';
  }

  // Get battery health recommendations
  List<String> getBatteryHealthRecommendations(int batteryLevel) {
    if (batteryLevel < 20) {
      return [
        'Charge device immediately',
        'Close unnecessary apps',
        'Reduce screen brightness',
        'Enable battery saver mode',
      ];
    } else if (batteryLevel < 40) {
      return [
        'Connect to charger soon',
        'Limit background app refresh',
        'Turn off vibration',
        'Disable location services',
      ];
    } else if (batteryLevel < 60) {
      return [
        'Monitor battery usage',
        'Reduce screen timeout',
        'Close unused apps',
        'Disable bluetooth and wifi',
      ];
    }
    return ['Battery level is good', 'Continue normal usage'];
  }
}
