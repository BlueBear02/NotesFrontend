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
import 'models/note.dart';

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

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notepad+++',
      debugShowCheckedModeBanner: false,
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

    setState(() {
      _homeWidget = home;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6A1B9A),
          ),
        ),
      );
    }

    return _homeWidget ?? const HomeScreen();
  }
}
