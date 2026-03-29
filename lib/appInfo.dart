
class AppInfo {
  final String packageName;
  final String appName;
  final List<int>? icon;
  bool isSelected;
  final bool isSystemApp;
  final DateTime? lastUsed;
  final int daysSinceUsed;

  AppInfo({
    required this.packageName,
    required this.appName,
    this.icon,
    this.isSelected = false,
    this.isSystemApp = false,
    this.lastUsed,
    this.daysSinceUsed = 0,
  });

  factory AppInfo.fromMap(Map<String, dynamic> map) {
    final lastUsedTime = map['lastUsedTime'] as int?;
    final lastUsed = lastUsedTime != null && lastUsedTime > 0
        ? DateTime.fromMillisecondsSinceEpoch(lastUsedTime)
        : null;

    return AppInfo(
      packageName: map['packageName'] as String,
      appName: map['name'] as String,
      icon: map['icon'] as List<int>?,
      isSelected: false,
      isSystemApp: map['isSystemApp'] as bool? ?? false,
      lastUsed: lastUsed,
      daysSinceUsed: (map['daysSinceUsed'] as num?)?.toInt() ?? 0,
    );
  }

}

