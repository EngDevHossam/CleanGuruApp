class Translations {
  static final Map<String, Map<String, String>> _translations = {
    'device_vitality': {
      'en': 'Device Vitality',
      'ar': 'حيوية الجهاز'
    },
    'optimize': {
      'en': 'Optimize',
      'ar': 'تحسين'
    },
    'system_health_overview': {
      'en': 'System Health Overview',
      'ar': 'نظرة عامة على صحة النظام'
    },
    'storage_analytics': {
      'en': 'Storage Used',
      'ar': 'التخزين المستخدم'
    },
    'memory_usage': {
      'en': 'Memory Usage',
      'ar': 'استخدام الذاكرة'
    },
    'performance_metrics': {
      'en': 'Performance Metrics',
      'ar': 'مقاييس الأداء'
    },
    'battery_status': {
      'en': 'Battery Status',
      'ar': 'حالة البطارية'
    }
  };

  static String translate(String key, {String lang = 'en'}) {
    return _translations[key]?[lang] ?? key;
  }
}