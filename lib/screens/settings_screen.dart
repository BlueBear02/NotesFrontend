import 'package:flutter/material.dart';
import '../services/preferences_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PreferencesService _prefsService = PreferencesService.instance;
  String _defaultHomeScreen = 'grid'; // 'grid', 'empty_note', 'last_opened'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final homeScreen = await _prefsService.getDefaultHomeScreen();
    setState(() {
      _defaultHomeScreen = homeScreen;
      _isLoading = false;
    });
  }

  Future<void> _saveDefaultHomeScreen(String value) async {
    await _prefsService.setDefaultHomeScreen(value);
    setState(() {
      _defaultHomeScreen = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFFF8F9FA),
        foregroundColor: const Color(0xFF6A1B9A),
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
                              color: const Color(0xFF6A1B9A),
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
                        RadioListTile<String>(
                          title: const Text('Notes Grid'),
                          subtitle: const Text('Show all your notes in a grid'),
                          value: 'grid',
                          groupValue: _defaultHomeScreen,
                          onChanged: (value) {
                            if (value != null) _saveDefaultHomeScreen(value);
                          },
                          activeColor: const Color(0xFF6A1B9A),
                        ),
                        RadioListTile<String>(
                          title: const Text('Empty Note'),
                          subtitle: const Text('Start with a blank note ready to write'),
                          value: 'empty_note',
                          groupValue: _defaultHomeScreen,
                          onChanged: (value) {
                            if (value != null) _saveDefaultHomeScreen(value);
                          },
                          activeColor: const Color(0xFF6A1B9A),
                        ),
                        RadioListTile<String>(
                          title: const Text('Last Opened Note'),
                          subtitle: const Text('Continue where you left off'),
                          value: 'last_opened',
                          groupValue: _defaultHomeScreen,
                          onChanged: (value) {
                            if (value != null) _saveDefaultHomeScreen(value);
                          },
                          activeColor: const Color(0xFF6A1B9A),
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
