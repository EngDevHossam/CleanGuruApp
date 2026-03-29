
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';




import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


class LanguageProvider extends ChangeNotifier {
  Locale _currentLocale = const Locale('en'); // Default to English

  Locale get currentLocale => _currentLocale;

  LanguageProvider() {
    // Initialize the language when the provider is created
    _initializeLanguage();
  }

  Future<void> _initializeLanguage() async {
    try {
      // First, try to load the saved language
      final prefs = await SharedPreferences.getInstance();
      final savedLanguageCode = prefs.getString('app_language_code');

      if (savedLanguageCode != null) {
        // If a saved language exists, use it
        await setLanguage(savedLanguageCode);
        return;
      }

      // If no saved language, try to use device's language
      final deviceLocale = Platform.localeName.split('_').first;

      // List of supported language codes
      final supportedLanguages = ['en', 'ar'];

      // Check if the device's language is supported
      if (supportedLanguages.contains(deviceLocale)) {
        await setLanguage(deviceLocale);
      } else {
        // Fallback to English if the device language is not supported
        await setLanguage('en');
      }
    } catch (e) {
      print('Error initializing language: $e');
      // Fallback to English in case of any error
      await setLanguage('en');
    }
  }

  Future<void> setLocale(Locale locale) async {
    try {
      // Validate the language code
      if (!['en', 'ar'].contains(locale.languageCode)) {
        locale = const Locale('en'); // Default to English
      }

      // Set the new locale
      _currentLocale = locale;

      // Save the language preference with a more specific key
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language_code', locale.languageCode);

      // Notify listeners about the language change
      notifyListeners();
    } catch (e) {
      print('Error setting locale: $e');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    try {
      // Validate the language code
      if (!['en', 'ar'].contains(languageCode)) {
        languageCode = 'en'; // Default to English
      }

      // Set the new locale
      _currentLocale = Locale(languageCode);

      // Save the language preference with a more specific key
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language_code', languageCode);

      // Notify listeners about the language change
      notifyListeners();
    } catch (e) {
      print('Error setting language: $e');
    }
  }
}

class AppLocalizations {
  static Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'dashboard_title': 'Dashboard',
      'storage_improvement': 'Improve Storage',
      'performance_boost': 'Performance Boost',
      'cache_cleaning': 'Clean Cache',
    },
    'ar': {
      'dashboard_title': 'لوحة التحكم',
      'storage_improvement': 'تحسين التخزين',
      'performance_boost': 'تحسين الأداء',
      'cache_cleaning': 'تنظيف التخزين المؤقت',
    }
  };

  static String translate(BuildContext context, String key) {
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);
    return _localizedValues[languageProvider.currentLocale.languageCode]?[key] ?? key;
  }
}