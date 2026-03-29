import 'dart:async';
import 'dart:io';

import 'package:clean_guru/settingScreen.dart';
import 'package:clean_guru/themeprovider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appOpenAd.dart';
import 'dashboard_screen.dart';
import 'languageProvider.dart';
import 'onboarding_screen.dart';


Future<void> main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize().then((InitializationStatus status) {
    // Just load the ad, don't show it yet
    AppOpenAdManager().loadAd();
  });
  if (Platform.isAndroid) {
    MobileAds.instance.initialize();
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Initialize SharedPreferences once
  final prefs = await SharedPreferences.getInstance();

  // Create and pre-initialize language provider
  final languageProvider = LanguageProvider();
  //await languageProvider.loadSavedLanguage();

  // Set up global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Caught framework error: ${details.exception}');
    print('Stack trace: ${details.stack}');
  };

  // Preload an App Open Ad
  final AppOpenAdManager appOpenAdManager = AppOpenAdManager();

  // Create ThemeProvider and load preferences
  final themeProvider = ThemeProvider();
  await themeProvider.loadThemeFromPrefs();

  // Run the app with additional error catching
  runZonedGuarded(() {
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageProvider>.value(
            value: languageProvider,
          ),
          ChangeNotifierProvider<ThemeProvider>.value(
            value: themeProvider,
          ),
        ],
        child: MyApp(appOpenAdManager: appOpenAdManager),
      ),
    );
  }, (error, stackTrace) {
    print('Uncaught error: $error');
    print('Stack trace: $stackTrace');
  });
}


class MyApp extends StatelessWidget {
  final AppOpenAdManager appOpenAdManager;

  const MyApp({
    Key? key,
    required this.appOpenAdManager,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer2<LanguageProvider, ThemeProvider>(
      builder: (context, languageProvider, themeProvider, child) {
        return MaterialApp(
          title: 'My App',
          locale: languageProvider.currentLocale,
          debugShowCheckedModeBanner: false,

          // Localization delegates
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          supportedLocales: const [
            Locale('en'), // English
            Locale('ar'), // Arabic
          ],

          // Theme configuration
          theme: ThemeProvider.lightTheme,
          darkTheme: ThemeProvider.darkBatteryTheme,
          themeMode: themeProvider.themeMode,

          home: const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  //AppOpenAd? _appOpenAd;
  bool _isAdLoaded = false;
  bool _isAdShowing = false;
  bool _isAdFailed = false;
  bool _hasProceeded = false;

  @override
  void initState() {
    super.initState();
    _loadOpenAd();

    _checkFirstTime();
  }

  Future<void> _loadOpenAd() async {
    print('Starting to load App Open Ad');

    // Use appropriate test ad unit ID based on platform
    final adUnitId = Platform.isAndroid
        ? 'ca-app-pub-3940256099942544/3419835294' // Android test ID
        : 'ca-app-pub-3940256099942544/5662855259'; // iOS test ID

    try {

    } catch (e) {
      print('Exception while loading Ad: $e');
      _isAdFailed = true;
      _proceedAfterAdOrTimeout();
    }

    // Set a slightly longer timeout to allow more time for ad to load
    Future.delayed(const Duration(seconds: 5), () {
      print('App Open Ad timeout reached');
      _proceedAfterAdOrTimeout();
    });
  }




  void _proceedAfterAdOrTimeout() {
    print('_proceedAfterAdOrTimeout called, hasProceeded=$_hasProceeded');
    if (!_hasProceeded) {
      _hasProceeded = true;
      _checkFirstTime();
    }
  }


  Future<void> _checkFirstTime() async {
    // Add a delay to show splash screen
    await Future.delayed(const Duration(seconds: 3));

    // Get shared preferences instance
    final prefs = await SharedPreferences.getInstance();

    // Check if it's the first time opening the app
    final isFirstTime = prefs.getBool('is_first_time') ?? true;

    // If ad is still showing, wait for it to complete
    if (_isAdLoaded && !_hasProceeded) {
      return; // Let the ad callback handle navigation
    }

    // Navigate to the appropriate screen
    if (isFirstTime) {
      // First time - show onboarding screen
      prefs.setBool('is_first_time', false);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        );
      }
    } else {
      // Not first time - go directly to dashboard
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/splashicon.png',
              width: 250,
              height: 250,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}