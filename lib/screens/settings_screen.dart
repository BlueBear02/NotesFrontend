import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PreferencesService _prefsService = PreferencesService.instance;
  String _defaultHomeScreen = 'grid'; // 'grid', 'empty_note', 'last_opened'
  int _themeColor = 0xFF6A1B9A; // Default purple
  bool _isDarkMode = false;
  bool _isLoading = true;

  // Available theme colors
  final List<Map<String, dynamic>> _themeColors = [
    {'name': 'Purple', 'value': 0xFF6A1B9A},
    {'name': 'Blue', 'value': 0xFF1976D2},
    {'name': 'Teal', 'value': 0xFF00796B},
    {'name': 'Green', 'value': 0xFF388E3C},
    {'name': 'Orange', 'value': 0xFFF57C00},
    {'name': 'Red', 'value': 0xFFD32F2F},
    {'name': 'Pink', 'value': 0xFFC2185B},
    {'name': 'Indigo', 'value': 0xFF303F9F},
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final homeScreen = await _prefsService.getDefaultHomeScreen();
    final themeColor = await _prefsService.getThemeColor();
    final darkMode = await _prefsService.getDarkMode();
    setState(() {
      _defaultHomeScreen = homeScreen;
      _themeColor = themeColor;
      _isDarkMode = darkMode;
      _isLoading = false;
    });
  }

  Future<void> _saveDefaultHomeScreen(String value) async {
    await _prefsService.setDefaultHomeScreen(value);
    setState(() {
      _defaultHomeScreen = value;
    });
  }

  Future<void> _saveThemeColor(int value) async {
    await _prefsService.setThemeColor(value);
    setState(() {
      _themeColor = value;
    });

    // Update the global theme notifier to rebuild the app with new theme
    themeColorNotifier.value = value;
  }

  Future<void> _toggleDarkMode(bool value) async {
    await _prefsService.setDarkMode(value);
    setState(() {
      _isDarkMode = value;
    });

    // Update the global dark mode notifier to rebuild the app with new theme
    darkModeNotifier.value = value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Default Home Screen Section
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.home,
                              color: Theme.of(context).colorScheme.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Default Home Screen',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose what you see when you open the app',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ignore: deprecated_member_use
                        RadioListTile<String>(
                          title: const Text('Notes Grid'),
                          subtitle: const Text('Show all your notes in a grid'),
                          value: 'grid',
                          groupValue: _defaultHomeScreen,
                          // ignore: deprecated_member_use
                          onChanged: (value) {
                            if (value != null) _saveDefaultHomeScreen(value);
                          },
                        ),
                        // ignore: deprecated_member_use
                        RadioListTile<String>(
                          title: const Text('Empty Note'),
                          subtitle: const Text('Start with a blank note ready to write'),
                          value: 'empty_note',
                          groupValue: _defaultHomeScreen,
                          // ignore: deprecated_member_use
                          onChanged: (value) {
                            if (value != null) _saveDefaultHomeScreen(value);
                          },
                        ),
                        // ignore: deprecated_member_use
                        RadioListTile<String>(
                          title: const Text('Last Opened Note'),
                          subtitle: const Text('Continue where you left off'),
                          value: 'last_opened',
                          groupValue: _defaultHomeScreen,
                          // ignore: deprecated_member_use
                          onChanged: (value) {
                            if (value != null) _saveDefaultHomeScreen(value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Dark Mode Section
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dark Mode',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isDarkMode ? 'Dark theme enabled' : 'Light theme enabled',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isDarkMode,
                          onChanged: _toggleDarkMode,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Theme Color Section
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.palette,
                              color: Color(_themeColor),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Theme Color',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose your favorite accent color',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _themeColors.map((colorData) {
                            final int colorValue = colorData['value'];
                            final String colorName = colorData['name'];
                            final bool isSelected = _themeColor == colorValue;

                            return InkWell(
                              onTap: () => _saveThemeColor(colorValue),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 80,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Color(colorValue).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? Color(colorValue) : Colors.grey[300]!,
                                    width: isSelected ? 3 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Color(colorValue),
                                        shape: BoxShape.circle,
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check, color: Colors.white, size: 24)
                                          : null,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      colorName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? Color(colorValue) : Colors.black87,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
