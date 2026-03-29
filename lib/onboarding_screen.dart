
import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'package:provider/provider.dart';

import 'languageProvider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}


class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    // Get the language provider to check current language
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.currentLocale.languageCode == 'en';

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (int page) {
              setState(() {
                _currentPage = page;
              });
            },
            children: [
              OnboardingPage(
                image: 'assets/onboarding1.png',
                title: isEnglish ? 'Welcome to Clean GURU' : 'مرحبًا بك في Clean GURU',
                description: isEnglish
                    ? 'Boost your device\'s performance effortlessly.\nManage storage, memory, and system health all in one place.'
                    : 'عزز أداء جهازك بسهولة.\nأدر التخزين والذاكرة وصحة النظام في مكان واحد.',
              ),
              OnboardingPage(
                image: 'assets/onboarding2.png',
                title: isEnglish
                    ? 'All-in-One\nOptimization Tools'
                    : 'أدوات التحسين\nالشاملة',
                description: isEnglish
                    ? 'Identify & clean up duplicate or large files.\nEnhance speed by freeing up RAM.\nMonitor & optimize your device\'s performance.'
                    : 'حدد ونظف الملفات المكررة أو الكبيرة.\nعزز السرعة عن طريق تحرير الذاكرة.\nراقب وحسّن أداء جهازك.',
              ),
              OnboardingPage(
                image: 'assets/onboarding3.png',
                title: isEnglish
                    ? 'Your Device, Your Control'
                    : 'جهازك، تحكمك',
                description: isEnglish
                    ? 'Take control of your device\'s health today. Optimize in one tap for a faster, cleaner experience!'
                    : 'تحكم في صحة جهازك اليوم. حسّن بنقرة واحدة لتجربة أسرع وأنظف!',
              ),
            ],
          ),
          Positioned(
            top: 50,
            right: isEnglish ? 20 : null,
            left: isEnglish ? null : 20,
            child: TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const DashboardScreen()),
                );
              },
              child: Text(
                isEnglish ? 'Skip' : 'تخطي',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                        (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _currentPage == index ? Colors.blue : Colors.grey.shade300,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                _currentPage == 2
                    ? ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const DashboardScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    isEnglish ? 'Get Started' : 'ابدأ الآن',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
                    : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    textDirection: isEnglish ? TextDirection.ltr : TextDirection.rtl,
                    children: [
                      TextButton(
                        onPressed: _currentPage == 0
                            ? null
                            : () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[800],
                        ),
                        child: Text(
                          isEnglish ? 'Back' : 'رجوع',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          isEnglish ? 'Next' : 'التالي',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingPage extends StatelessWidget {
  final String image;
  final String title;
  final String description;

  const OnboardingPage({
    super.key,
    required this.image,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            image,
            height: 300,
          ),
          const SizedBox(height: 40),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
