import 'package:flutter/material.dart';

import 'appOpenAd.dart';


class AppLifecycleReactor {
  final AppOpenAdManager appOpenAdManager;

  AppLifecycleReactor({required this.appOpenAdManager});

  void listenToAppStateChanges() {
    WidgetsBinding.instance.addObserver(AppLifecycleObserver(appOpenAdManager));
  }
}

class AppLifecycleObserver extends WidgetsBindingObserver {
  final AppOpenAdManager appOpenAdManager;

  AppLifecycleObserver(this.appOpenAdManager);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Try to show an app open ad if the app is being resumed and
    // we're not already showing an app open ad.
    if (state == AppLifecycleState.resumed) {
      appOpenAdManager.showAdIfAvailable();
    }
  }
}