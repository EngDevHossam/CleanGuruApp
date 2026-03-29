

import 'package:flutter/material.dart';

import 'memoryScreen.dart';

class AppRamUsage {
  final String name;
  final String ramUsage;
  final IconData? icon;
  bool isSelected;
  final String packageName;

  AppRamUsage({
    required this.name,
    required this.ramUsage,
    this.icon,
    required this.isSelected,
    required this.packageName,
  });

  factory AppRamUsage.fromMap(Map<String, dynamic> map) {
    return AppRamUsage(
      name: map['name'] as String,
      ramUsage: formatMemorySize(map['ramUsage'] as int),
      icon: Icons.android,
      packageName: map['packageName'] as String,
      isSelected: true,
    );
  }
}
