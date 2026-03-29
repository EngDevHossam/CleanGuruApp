

// Add this class to store unused app information
import 'memoryScreen.dart';

class UnusedAppInfo {
  final String name;
  final String packageName;
  final String ramUsage;
  final DateTime lastUsed;
  final int daysSinceUsed;
  bool isSelected;

  UnusedAppInfo({
    required this.name,
    required this.packageName,
    required this.ramUsage,
    required this.lastUsed,
    required this.daysSinceUsed,
    this.isSelected = true,
  });

  factory UnusedAppInfo.fromMap(Map<String, dynamic> map) {
    final lastUsedTime = map['lastUsedTime'] as int;
    final lastUsed = DateTime.fromMillisecondsSinceEpoch(lastUsedTime);

    return UnusedAppInfo(
      name: map['name'] as String,
      packageName: map['packageName'] as String,
      ramUsage: formatMemorySize(map['ramUsage'] as int),
      lastUsed: lastUsed,
      daysSinceUsed: map['daysSinceUsed'] as int,
      isSelected: true,
    );
  }
}
