import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  bool _isDarkModeForBattery = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkModeForBattery => _isDarkModeForBattery;

  // Light theme
  static final lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
    ),
  );

  // Dark theme optimized for battery
  static final darkBatteryTheme = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blueGrey,
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    colorScheme: ColorScheme.dark(
      background: Colors.black,
      surface: Colors.black,
    ),
  );

  // Method to toggle dark mode for battery optimization
  Future<void> toggleBatteryOptimizationMode() async {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;

    _isDarkModeForBattery = _themeMode == ThemeMode.dark;

    // Save preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('batteryOptimizationMode', _isDarkModeForBattery);

    // Notify listeners about theme change
    notifyListeners();
  }

  // Initialize theme from saved preferences
  Future<void> loadThemeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkModeForBattery = prefs.getBool('batteryOptimizationMode') ?? false;

    _themeMode = _isDarkModeForBattery
        ? ThemeMode.dark
        : ThemeMode.light;

    notifyListeners();
  }
}