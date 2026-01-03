import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _selectedCategoriesKey = 'selected_categories';
  static const String _defaultHomeScreenKey = 'default_home_screen';
  static const String _lastOpenedNoteIdKey = 'last_opened_note_id';
  static const String _themeColorKey = 'theme_color';
  static const String _darkModeKey = 'dark_mode';

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

  // Default home screen preference
  Future<void> setDefaultHomeScreen(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultHomeScreenKey, value);
  }

  Future<String> getDefaultHomeScreen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultHomeScreenKey) ?? 'grid';
  }

  // Last opened note preference
  Future<void> setLastOpenedNoteId(int? noteId) async {
    final prefs = await SharedPreferences.getInstance();
    if (noteId != null) {
      await prefs.setInt(_lastOpenedNoteIdKey, noteId);
    } else {
      await prefs.remove(_lastOpenedNoteIdKey);
    }
  }

  Future<int?> getLastOpenedNoteId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastOpenedNoteIdKey);
  }

  // Theme color preference
  Future<void> setThemeColor(int colorValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeColorKey, colorValue);
  }

  Future<int> getThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_themeColorKey) ?? 0xFF6A1B9A; // Default purple
  }

  // Dark mode preference
  Future<void> setDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, isDark);
  }

  Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false; // Default light mode
  }
}
