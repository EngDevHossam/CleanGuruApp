

import 'dart:io';

class AdHelper {
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-1439642083038769/1025667470'; // Test ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  // Replace with your actual Ad Unit IDs when going to production
  static String get productionBannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy'; // Your actual ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get appOpenAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-1439642083038769/7917275239';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/5575463023'; // Test ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}