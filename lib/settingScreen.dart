import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:provider/provider.dart';

import 'languageProvider.dart';



class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  Widget _buildSettingItem({
    required BuildContext context,
    required String titleEn,
    required String titleAr,
    required IconData icon,
    String? valueEn,
    String? valueAr,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        color: Colors.blue,
        size: 24,
      ),
      title: Text(
        isEnglish ? titleEn : titleAr,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.black87,
        ),
      ),
      trailing: trailing ?? (valueEn != null
          ? Text(
        isEnglish ? valueEn : valueAr ?? valueEn,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 14,
        ),
      )
          : const Icon(Icons.chevron_right, color: Colors.grey)),
    );
  }

  Widget _buildAppItem({
    required BuildContext context,
    required String imagePath,
    required String titleEn,
    required String titleAr,
    required String subtitleEn,
    required String subtitleAr,
    required VoidCallback onGetPressed,
    bool isFirstApp = false,
  }) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              imagePath,
              width: 50,
              height: 50,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEnglish ? titleEn : titleAr,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  isEnglish ? subtitleEn : subtitleAr,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onGetPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isEnglish ? 'Get' : 'احصل',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSpecificApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.kitaba'
        : 'https://apps.apple.com/eg/app/%D9%83%D8%AA%D8%A7%D8%A8%D8%A9-%D8%B9%D9%84%D9%89-%D8%A7%D9%84%D8%B5%D9%88%D8%B1-%D8%AA%D8%B5%D9%85%D9%8A%D9%85-%D8%B5%D9%88%D8%B1/id958075714';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openZakhrfaApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.rabapp.zakhrapha'
        : 'https://apps.apple.com/eg/app/%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%A7%D9%84%D9%83%D8%AA%D8%A7%D8%A8%D9%87/id6476085334';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openCurrenceyConverterApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.rabapp.currency.converter'
        : 'https://apps.apple.com/eg/app/%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%A7%D9%84%D9%83%D8%AA%D8%A7%D8%A8%D9%87/id6476085334';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openFitcalApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.arabpp.fitcalHealth'
        : 'https://apps.apple.com/eg/app/%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%A7%D9%84%D9%83%D8%AA%D8%A7%D8%A8%D9%87/id6476085334';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openStepCounterApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.rabapp.stepcounter'
        : 'https://apps.apple.com/eg/app/%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%A7%D9%84%D9%83%D8%AA%D8%A7%D8%A8%D9%87/id6476085334';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openWeatherApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.rabapp.weather.now'
        : 'https://apps.apple.com/eg/app/%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%B2%D8%AE%D8%B1%D9%81%D9%87-%D8%A7%D9%84%D9%83%D8%AA%D8%A7%D8%A8%D9%87/id6476085334';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }
  Future<void> _openSpeedTestApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.rabapp.networkspeed.android'
        : 'https://apps.apple.com/eg/app/speedtest-%D8%B3%D8%B1%D8%B9%D8%A9-%D8%A7%D9%84%D9%86%D8%AA/id1635139320';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openMuslimApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.arabapps.qibla2'
        : 'https://apps.apple.com/eg/app/speedtest-%D8%B3%D8%B1%D8%B9%D8%A9-%D8%A7%D9%84%D9%86%D8%AA/id1635139320';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }


  Future<void> _openWalletApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.rabapp.mybudget'
        : 'https://apps.apple.com/eg/app/wallet-budget-daily-wallet/id6741729309';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openSendSnapApp() async {
    // Use the appropriate URL based on the platform
    final String url = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=com.threearabapp.Sendsnap'
        : 'https://apps.apple.com/eg/app/sendsnap-%D8%B5%D9%88%D8%B1/id6736941131';

    final Uri uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Failed to launch URL
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Future<void> _openRateUs() async {
    String url;

    if (Platform.isAndroid) {
      // Replace with your app's package name
      url = 'https://play.google.com/store/apps/details?id=com.arabapp.clean_guru';
    } else if (Platform.isIOS) {
      // Replace with your App Store ID
      url = 'https://apps.apple.com/app/id123456789?action=write-review';
    } else {
      print('Platform not supported for ratings');
      return;
    }

    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('Could not launch $uri');
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

/*
  Future<void> _contactSupport() async {
    final Uri emailUri = Uri(
        scheme: 'mailto',
        path: 'support@3rabapp.com',
        queryParameters: {
          'subject': 'Support Request', // Pre-filled subject
          'body': 'Hi Support Team,\n\n' // Pre-filled email body
        }
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        print('Could not launch email client');
      }
    } catch (e) {
      print('Error launching email client: $e');
    }
  }
*/

  Future<void> _contactSupport() async {
    try {
      // Get app version information
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String appVersion = packageInfo.version;

      // Get device language and OS
      String deviceLanguage = Platform.localeName.split('_')[0]; // Get language code only
      String osVersion = Platform.operatingSystem;

      final Uri emailUri = Uri(
          scheme: 'mailto',
          path: 'support@3rabapp.com',
          queryParameters: {
            'subject': 'Feedback [Clean Guru]',
            'body': '''Hello there,
Feedback details:



...


OS version: ${osVersion.substring(0, 1).toUpperCase()}${osVersion.substring(1)}
App version: $appVersion
App language: ${deviceLanguage.substring(0, 1).toUpperCase()}${deviceLanguage.substring(1)}'''
          }
      );

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        print('Could not launch email client');
      }
    } catch (e) {
      print('Error launching email client: $e');
    }
  }

  Future<void> _contactSupportDetailed() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      // Collect comprehensive app and device information
      Map<String, String> deviceInfo = {
        'App Version': '${packageInfo.version} (${packageInfo.buildNumber})',
        'App Name': packageInfo.appName,
        'Package Name': packageInfo.packageName,
        'Platform': Platform.operatingSystem,
        'OS Version': Platform.operatingSystemVersion,
        'Language': Platform.localeName,
        'Number of Processors': Platform.numberOfProcessors.toString(),
      };

      // Format device info for email
      String deviceInfoString = deviceInfo.entries
          .map((entry) => '- ${entry.key}: ${entry.value}')
          .join('\n');

      final Uri emailUri = Uri(
          scheme: 'mailto',
          path: 'support@3rabapp.com',
          queryParameters: {
            'subject': '3rab App Support - v${packageInfo.version}',
            'body': '''Hi Support Team,

I'm experiencing an issue with the 3rab App and would appreciate your assistance.

DEVICE & APP INFORMATION:
$deviceInfoString

ISSUE DETAILS:
Problem Description: [Please describe your issue]

Steps to Reproduce:
1. [First step]
2. [Second step]
3. [Third step]

Expected Result: [What should happen]
Actual Result: [What actually happens]

Screenshots: [If applicable, please attach screenshots]

Additional Notes: [Any other relevant information]

Thank you for your time and support!

Best regards'''
          }
      );

      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        print('Could not launch email client');
      }
    } catch (e) {
      print('Error launching email client: $e');
    }
  }

  Future<void> _shareWithFriends() async {
    // App details
    final String appName = 'My App'; // Replace with your app name
    final String storeLink = Platform.isAndroid
        ? 'https://play.google.com/store/apps/details?id=your.package.name' // Replace with your app's Play Store link
        : 'https://apps.apple.com/app/id123456789'; // Replace with your app's App Store link

    // Share text
    final String shareText = 'Check out $appName! Download it from: $storeLink';

    // Use share_plus package to show platform's share sheet
    await Share.share(shareText, subject: 'Share $appName with Friends');
  }

/*
  void _switchLanguage(BuildContext context) {
    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Toggle between English and Arabic
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';
    final newLocale = isEnglish ? const Locale('ar') : const Locale('en');

    // Update the locale using the provider
    languageProvider.setLocale(newLocale);

    // Show confirmation toast
    final newLanguage = isEnglish ? 'Arabic' : 'English';
    Fluttertoast.showToast(
      msg: 'Language changed to $newLanguage',
      toastLength: Toast.LENGTH_SHORT,
    );
  }
*/

/*
  void _switchLanguage(BuildContext context) {
    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Toggle between English and Arabic
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';
    final newLocale = isEnglish ? const Locale('ar') : const Locale('en');

    // Update the locale using the provider
    languageProvider.setLocale(newLocale);

    // Ensure the dashboard screen rebuild is forced
    Navigator.pop(context);

    // Show confirmation toast
    final newLanguage = isEnglish ? 'Arabic' : 'English';
    Fluttertoast.showToast(
      msg: 'Language changed to $newLanguage',
      toastLength: Toast.LENGTH_SHORT,
    );
  }
*/
/*
  void _switchLanguage(BuildContext context) {
    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Toggle between English and Arabic
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';
    final newLocale = isEnglish ? const Locale('ar') : const Locale('en');

    // Update the locale using the provider
    languageProvider.setLocale(newLocale);

    // Ensure the dashboard screen rebuild is forced
    Navigator.pop(context);

    // Show confirmation toast
    final newLanguage = isEnglish ? 'Arabic' : 'English';
    Fluttertoast.showToast(
      msg: 'Language changed to $newLanguage',
      toastLength: Toast.LENGTH_SHORT,
    );
  }
*/

/*
  void _switchLanguage(BuildContext context) {
    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Toggle between English and Arabic
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';
    final newLocale = isEnglish ? const Locale('ar') : const Locale('en');
    final newLanguage = isEnglish ? 'Arabic' : 'English';

    // Update the locale using the provider
    languageProvider.setLocale(newLocale);

    // Show confirmation toast
    Fluttertoast.showToast(
      msg: 'Language changed to $newLanguage',
      toastLength: Toast.LENGTH_SHORT,
    );

    // Return to previous screen after a brief delay to allow locale change to apply
    Future.delayed(Duration(milliseconds: 300), () {
      Navigator.pop(context);
    });
  }
*/

  void _switchLanguage(BuildContext context) {
    // Show a loading indicator first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    // Get the language provider
    final languageProvider = Provider.of<LanguageProvider>(context, listen: false);

    // Toggle between English and Arabic
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';
    final newLocale = isEnglish ? const Locale('ar') : const Locale('en');
    final newLanguage = isEnglish ? 'Arabic' : 'English';

    // Use a microtask to allow Flutter to process the UI update
    Future.microtask(() async {
      try {
        // Update the locale using the provider
        await languageProvider.setLocale(newLocale);

        // Wait a moment for the language change to apply
        await Future.delayed(Duration(milliseconds: 500));

        // Close the loading dialog
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }

        // Then navigate back safely
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }

        // Show confirmation toast
        Fluttertoast.showToast(
          msg: 'Language changed to $newLanguage',
          toastLength: Toast.LENGTH_SHORT,
        );
      } catch (e) {
        // If something goes wrong, ensure dialogs are closed
        print('Error changing language: $e');
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Color(0xFFF2F9FF),
          centerTitle: true, // This centers the title

          title: Text(
              Provider.of<LanguageProvider>(context).currentLocale.languageCode == 'en'
                  ? 'Settings'
                  : 'الإعدادات',
            style: TextStyle(
              color: Colors.black, // Make text black
            ),
          ),
/*
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // Safely navigate back with a slight delay
              Future.delayed(Duration(milliseconds: 100), () {
                if (Navigator.canPop(context)) {
                  Navigator.of(context).pop();
                }
              });
            },
          ),
*/
        ),
        body: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            Provider.of<LanguageProvider>(context).currentLocale.languageCode == 'en'
                ? 'In app'
                : 'داخل التطبيق',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ),
        _buildSettingItem(
          context: context,
          titleEn: 'Language',
          titleAr: 'اللغة',
          icon: Icons.language,
          valueEn: 'English',
          valueAr: 'العربية',
          onTap: () {
            _switchLanguage(context);
          },
        ),

        const Divider(height: 1),
        _buildSettingItem(
          context: context,
          titleEn: 'Rate us',
          titleAr: 'قيّمنا',
          icon: Icons.star_outline,
          onTap: _openRateUs,
        ),
        const Divider(height: 1),
        _buildSettingItem(
          context: context,
          titleEn: 'Have a problem? contact us',
          titleAr: 'هل تواجه مشكلة؟ تواصل معنا',
          icon: Icons.headset_mic_outlined,
         onTap: _contactSupport,
         // onTap: _contactSupportDetailed
        ),
        const Divider(height: 1),
        _buildSettingItem(
          context: context,
          titleEn: 'Share with friends',
          titleAr: 'مشاركة مع الأصدقاء',
          icon: Icons.telegram,
          trailing: const Icon(Icons.share, color: Colors.grey),
          onTap: _shareWithFriends,
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            Provider.of<LanguageProvider>(context).currentLocale.languageCode == 'en'
                ? 'Check out apps on app store'
                : 'تصفح التطبيقات في متجر التطبيقات',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ),
        Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
    children: [
    _buildAppItem(
    context: context,
    imagePath: 'assets/ketaba.png',
    titleEn: 'ketaba',
    titleAr: 'كتابة',
    subtitleEn: 'Pic design & large arabic fonts',
    subtitleAr: 'تصميم الصور وخطوط عربية كبيرة',
    onGetPressed: _openSpecificApp,
    ),
    _buildAppItem(
    context: context,
    imagePath: 'assets/zakhrfa.png',
    titleEn: 'zakhrfa',
    titleAr: 'زخرفة',
    subtitleEn: 'Pic design & large arabic fonts',
    subtitleAr: 'تصميم الصور وخطوط عربية كبيرة',
      onGetPressed: _openZakhrfaApp,
    ),
      _buildAppItem(
        context: context,
        imagePath: 'assets/speedtest.png',
        titleEn: 'Speed Test',
        titleAr: 'سرعة النت',
        subtitleEn: 'Network speed test tool',
        subtitleAr: 'أداة اختبار سرعة الشبكة',
        onGetPressed: _openSpeedTestApp,
      ),
      _buildAppItem(
        context: context,
        imagePath: 'assets/wallet.png',
        titleEn: 'Budget Wallet',
        titleAr: 'الميزانية',
        subtitleEn: 'Personal finance manager',
        subtitleAr: 'مدير المالية الشخصية',
        onGetPressed: _openWalletApp,
      ),
      _buildAppItem(
        context: context,
        imagePath: 'assets/sendsnap.png',
        titleEn: 'SendSnap',
        titleAr: 'إرسال سناب',
        subtitleEn: 'Quick photo messaging',
        subtitleAr: 'مراسلة الصور السريعة',
        onGetPressed: _openSendSnapApp,
      ),
      _buildAppItem(
        context: context,
        imagePath: 'assets/currency.png',
        titleEn: 'Currency Converter',
        titleAr: 'تحويل العملات',
        subtitleEn: 'Currency to another easy and fast',
        subtitleAr: 'تحويل العملات بسرعه وسهوله',
        onGetPressed: _openCurrenceyConverterApp,
      ),

      _buildAppItem(
        context: context,
        imagePath: 'assets/fitcal.png',
        titleEn: 'Fitcal',
        titleAr: 'حرق الدهون',
        subtitleEn: 'Fit Cal makes it easy to track food, calories',
        subtitleAr: 'يجعل تطبيق Fit Cal من السهل تتبع الطعام والسعرات الحرارية',
        onGetPressed: _openFitcalApp,
      ),

      _buildAppItem(
        context: context,
        imagePath: 'assets/khatwat.png',
        titleEn: 'Steps',
        titleAr: 'خطوات',
        subtitleEn: 'Steps App, the perfect pedometer and fitness tracker app ',
        subtitleAr: 'تطبيق Steps، التطبيق المثالي لقياس الخطوات وتتبع اللياقة البدنية',
        onGetPressed: _openStepCounterApp,
      ),
      _buildAppItem(
        context: context,
        imagePath: 'assets/weather.png',
        titleEn: 'Weather Now',
        titleAr: 'الطقس',
        subtitleEn: 'Simply check the weather forecast',
        subtitleAr: 'فقط تحقق من توقعات الطقس',
        onGetPressed: _openWeatherApp,
      ),

      _buildAppItem(
        context: context,
        imagePath: 'assets/qibla.png',
        titleEn: 'Muslim - qibla direction',
        titleAr: 'اتجاه القبله',
        subtitleEn: 'Shows you the accurate direction of Qibla using GPS technology.',
        subtitleAr: 'تعرض لك اتجاه القبلة بدقة باستخدام تقنية GPS.',
        onGetPressed: _openMuslimApp,
      ),
    ],
    ),
        ),
              ],
          ),
        ),
    );
  }
}

// LanguageProvider Class
