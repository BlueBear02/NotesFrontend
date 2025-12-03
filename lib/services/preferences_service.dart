import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _selectedCategoriesKey = 'selected_categories';

  static PreferencesService? _instance;
  static PreferencesService get instance {
    _instance ??= PreferencesService._();
    return _instance!;
  }

  PreferencesService._();

  Future<void> saveSelectedCategories(Set<String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedCategoriesKey, categories.toList());
  }

  Future<Set<String>> loadSelectedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_selectedCategoriesKey);
    return list?.toSet() ?? {};
  }

  Future<void> clearSelectedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedCategoriesKey);
  }
}
