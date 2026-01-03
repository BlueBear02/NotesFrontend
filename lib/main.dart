import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'screens/home_screen.dart';
import 'screens/desktop_notes_screen.dart';
import 'screens/note_form_screen.dart';
import 'services/preferences_service.dart';
import 'services/database_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Configure window for desktop
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Try to load .env file, but continue if it doesn't exist (local-only mode)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    // .env file not found - app will run in local-only mode without sync
    debugPrint('No .env file found - running in local-only mode');
  }
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

// Global theme notifiers
final themeColorNotifier = ValueNotifier<int>(0xFF6A1B9A);
final darkModeNotifier = ValueNotifier<bool>(false);

class _MainAppState extends State<MainApp> {
  final PreferencesService _prefsService = PreferencesService.instance;

  @override
  void initState() {
    super.initState();
    _loadThemeSettings();
    // Listen for theme changes
    themeColorNotifier.addListener(_onThemeChanged);
    darkModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeColorNotifier.removeListener(_onThemeChanged);
    darkModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  Future<void> _loadThemeSettings() async {
    final color = await _prefsService.getThemeColor();
    final darkMode = await _prefsService.getDarkMode();
    themeColorNotifier.value = color;
    darkModeNotifier.value = darkMode;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notepad+++',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Color(themeColorNotifier.value),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(themeColorNotifier.value),
          brightness: Brightness.light,
        ).copyWith(
          surface: const Color(0xFFFAFAFA), // Very light gray instead of tinted
          surfaceContainerLowest: const Color(0xFFFFFFFF),
          surfaceContainerLow: const Color(0xFFF5F5F5),
          surfaceContainer: const Color(0xFFF0F0F0),
          surfaceContainerHigh: const Color(0xFFECECEC),
          surfaceContainerHighest: const Color(0xFFE8E8E8),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        primaryColor: Color(themeColorNotifier.value),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(themeColorNotifier.value),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: darkModeNotifier.value ? ThemeMode.dark : ThemeMode.light,
      home: const InitialScreen(),
    );
  }
}

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  final PreferencesService _prefsService = PreferencesService.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  bool _isLoading = true;
  Widget? _homeWidget;

  @override
  void initState() {
    super.initState();
    _determineHomeScreen();
  }

  Future<void> _determineHomeScreen() async {
    try {
      final defaultHomeScreen = await _prefsService.getDefaultHomeScreen();

      Widget home;

      switch (defaultHomeScreen) {
        case 'empty_note':
          // Open directly to a new empty note
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
            home = const DesktopNotesScreen(createNew: true);
          } else {
            // Mobile uses NoteFormScreen for new notes
            home = const NoteFormScreen();
          }
          break;

        case 'last_opened':
          // Try to open the last opened note
          final lastNoteId = await _prefsService.getLastOpenedNoteId();
          if (lastNoteId != null) {
            try {
              final notes = await _dbHelper.readAll();
              final note = notes.firstWhere((n) => n.id == lastNoteId);
              if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
                home = DesktopNotesScreen(initialNote: note);
              } else {
                // Mobile uses NoteFormScreen for editing
                home = NoteFormScreen(note: note);
              }
            } catch (e) {
              // Note not found, fall back to grid
              home = const HomeScreen();
            }
          } else {
            // No last note, fall back to grid
            home = const HomeScreen();
          }
          break;

        case 'grid':
        default:
          // Default grid view
          home = const HomeScreen();
          break;
      }

      if (mounted) {
        setState(() {
          _homeWidget = home;
          _isLoading = false;
        });
      }
    } catch (e) {
      // On any error, default to home screen
      if (mounted) {
        setState(() {
          _homeWidget = const HomeScreen();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    return _homeWidget ?? const HomeScreen();
  }
}
