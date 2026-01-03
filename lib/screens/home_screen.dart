import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'dart:convert';
import 'package:fleather/fleather.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/preferences_service.dart';
import '../widgets/custom_title_bar.dart';
import 'note_form_screen.dart';
import 'desktop_notes_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SyncService _syncService = SyncService.instance;
  final AuthService _authService = AuthService.instance;
  final PreferencesService _prefsService = PreferencesService.instance;
  List<Note> _notes = [];
  bool _isLoading = true;
  String _syncStatus = '';
  String? _errorMessage;

  // Filter and sort
  Set<String> _selectedCategories = {}; // Multi-select: empty = show all
  String _sortBy = 'updated'; // 'created', 'updated', 'category', 'title'
  String _sortOrder = 'desc'; // 'asc' or 'desc'
  bool _showHiddenNotes = false;
  bool _showFavouritesOnly = false;
  Set<String> _availableCategories = {};

  @override
  void initState() {
    super.initState();
    _loadSelectedCategories().then((_) {
      _loadNotesFromLocal().then((_) {
        // Load notes first, then sync in background without blocking UI
        _syncInBackground();
      });
    });
  }

  Future<void> _loadSelectedCategories() async {
    final categories = await _prefsService.loadSelectedCategories();
    setState(() {
      _selectedCategories = categories;
    });
  }

  Future<void> _saveSelectedCategories() async {
    await _prefsService.saveSelectedCategories(_selectedCategories);
  }

  String _getDisplayTitle(Note note) {
    if (note.title.trim().isNotEmpty) {
      return note.title;
    }
    // Generate title from content for display
    try {
      final deltaJson = note.getContentAsDelta();
      final doc = ParchmentDocument.fromJson(jsonDecode(deltaJson));
      final plainText = doc.toPlainText().trim();
      if (plainText.isEmpty) {
        return 'Untitled';
      }
      final title = plainText.length > 50
          ? '${plainText.substring(0, 50)}...'
          : plainText;
      return title.replaceAll('\n', ' ');
    } catch (e) {
      return 'Untitled';
    }
  }

  Future<void> _syncInBackground() async {
    // Skip sync UI entirely if API is not configured (local-only mode)
    if (!ApiService.isConfigured) {
      return;
    }

    setState(() {
      _syncStatus = 'Syncing...';
    });

    try {
      final result = await _syncService.syncWithBackend();

      if (result.success) {
        await _loadNotesFromLocal();
        setState(() => _syncStatus = '✓ Synced');

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _syncStatus = '');
        });
      } else {
        setState(() => _syncStatus = 'Offline');
      }
    } catch (e) {
      setState(() => _syncStatus = 'Offline');
    }
  }

  Future<void> _loadAndSync() async {
    await _loadNotesFromLocal();
    await _syncInBackground();
  }

  Future<void> _loadNotesFromLocal() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final notes = await _dbHelper.readAll();
      setState(() {
        _notes = notes;
        _isLoading = false;
      });
      _extractCategories();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _extractCategories() {
    // Filter notes based on hidden status first
    final visibleNotes = _showHiddenNotes
        ? _notes.where((note) => note.isHidden)
        : _notes.where((note) => !note.isHidden);

    final categories = visibleNotes
        .where((note) => note.category != null && note.category!.isNotEmpty)
        .map((note) => note.category!)
        .toSet();

    // Add "Uncategorised" if there are notes without a category in the visible notes
    final hasUncategorised = visibleNotes.any((note) => note.category == null || note.category!.isEmpty);
    if (hasUncategorised) {
      categories.add('Uncategorised');
    }

    // Check if we need to remove invalid categories BEFORE modifying
    final invalidCategories = _selectedCategories.where((cat) => !categories.contains(cat)).toSet();

    setState(() {
      _availableCategories = categories;
      _selectedCategories.removeWhere((cat) => !categories.contains(cat));
    });

    // Save updated selected categories if any were removed
    if (invalidCategories.isNotEmpty) {
      _saveSelectedCategories();
    }
  }

  List<Note> get _filteredAndSortedNotes {
    var filtered = _notes.toList();

    // Filter by hidden status: show ONLY hidden notes when toggled, hide them otherwise
    if (_showHiddenNotes) {
      filtered = filtered.where((note) => note.isHidden).toList();
    } else {
      filtered = filtered.where((note) => !note.isHidden).toList();
    }

    // Filter by favourites
    if (_showFavouritesOnly) {
      filtered = filtered.where((note) => note.isFavourite).toList();
    }

    // Apply category filter: if categories selected, show only those
    if (_selectedCategories.isNotEmpty) {
      filtered = filtered.where((note) {
        if (_selectedCategories.contains('Uncategorised')) {
          // Show uncategorised notes or notes in other selected categories
          return (note.category == null || note.category!.isEmpty) ||
                 (note.category != null && _selectedCategories.contains(note.category));
        } else {
          // Show only notes in selected categories
          return note.category != null && _selectedCategories.contains(note.category);
        }
      }).toList();
    }

    // Apply sort
    filtered.sort((a, b) {
      int comparison = 0;
      switch (_sortBy) {
        case 'created':
          comparison = a.createdAt.compareTo(b.createdAt);
          break;
        case 'updated':
          comparison = a.updatedAt.compareTo(b.updatedAt);
          break;
        case 'category':
          final aCat = a.category ?? '';
          final bCat = b.category ?? '';
          comparison = aCat.compareTo(bCat);
          break;
        case 'title':
          comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
      }
      return _sortOrder == 'asc' ? comparison : -comparison;
    });

    return filtered;
  }

  Future<void> _navigateToCreateNote() async {
    // Use desktop split view on Windows/Mac/Linux, mobile full screen on mobile
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => DesktopNotesScreen(
            createNew: true,
            showHiddenNotesInitially: _showHiddenNotes,
          ),
        ),
      );
      // Update showHiddenNotes state if it was changed
      if (result != null && result != _showHiddenNotes) {
        setState(() {
          _showHiddenNotes = result;
        });
      }
      // Reload after returning from desktop view
      await _loadNotesFromLocal();
    } else {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const NoteFormScreen()),
      );

      if (result == true) {
        // Reload from local (note was already saved there)
        await _loadNotesFromLocal();
      }
    }
  }

  Future<void> _navigateToEditNote(Note note) async {
    // Use desktop split view on Windows/Mac/Linux, mobile full screen on mobile
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => DesktopNotesScreen(
            initialNote: note,
            showHiddenNotesInitially: _showHiddenNotes,
          ),
        ),
      );
      // Update showHiddenNotes state if it was changed
      if (result != null && result != _showHiddenNotes) {
        setState(() {
          _showHiddenNotes = result;
        });
      }
      // Reload after returning from desktop view
      await _loadNotesFromLocal();
    } else {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NoteFormScreen(note: note),
        ),
      );

      if (result == true) {
        // Reload from local (note was updated or deleted)
        await _loadNotesFromLocal();
      }
    }
  }

  Future<void> _showDeleteDialog(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${note.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteNote(note);
    }
  }

  Future<void> _deleteNote(Note note) async {
    try {
      // Try to delete from backend first (if note has server_id)
      if (note.serverId != null) {
        try {
          await ApiService.instance.deleteNote(note.serverId!);
          // Backend succeeded, hard delete from local
          await _dbHelper.hardDelete(note.id!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Note deleted ✓')),
            );
          }
        } catch (e) {
          // Backend failed (offline) - soft delete locally
          await _dbHelper.delete(note.id!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Deleted offline - will sync when online'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        // Note was created offline, just delete locally
        await _dbHelper.hardDelete(note.id!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note deleted ✓')),
          );
        }
      }

      // Reload notes
      await _loadNotesFromLocal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showContextMenu(BuildContext context, TapDownDetails details, Note note) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          0,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Delete'),
            ],
          ),
          onTap: () {
            _deleteNote(note);
          },
        ),
      ],
    );
  }

  Future<void> _showCategoryFilterDialog() async {
    final tempSelected = Set<String>.from(_selectedCategories);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filter Categories'),
          content: SizedBox(
            width: double.maxFinite,
            child: _availableCategories.isEmpty
                ? const Text('No categories available')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      CheckboxListTile(
                        title: const Text('Show All', style: TextStyle(fontWeight: FontWeight.bold)),
                        value: tempSelected.isEmpty,
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              tempSelected.clear();
                            }
                          });
                        },
                      ),
                      const Divider(),
                      ..._availableCategories.map((category) => CheckboxListTile(
                        title: Text(category),
                        value: tempSelected.contains(category),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              tempSelected.add(category);
                            } else {
                              tempSelected.remove(category);
                            }
                          });
                        },
                      )),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedCategories = tempSelected;
                });
                _saveSelectedCategories();
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleShowHiddenNotes() async {
    if (!_showHiddenNotes) {
      // Trying to show hidden notes - require authentication
      final authenticated = await _authService.authenticate(
        reason: 'Authenticate to view hidden notes',
      );

      if (authenticated) {
        setState(() {
          _showHiddenNotes = true;
        });
        _extractCategories();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Hiding hidden notes again - no auth needed
      setState(() {
        _showHiddenNotes = false;
      });
      _extractCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CustomTitleBar(),
        Expanded(
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            appBar: AppBar(
        title: Row(
          children: [
            const Text('Notes'),
            if (_syncStatus.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                _syncStatus,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFFF8F9FA),
        foregroundColor: const Color(0xFF6A1B9A),
        actions: [
          // Show/Hide hidden notes button
          IconButton(
            icon: Icon(_showHiddenNotes ? Icons.visibility_off : Icons.visibility),
            onPressed: _toggleShowHiddenNotes,
            tooltip: _showHiddenNotes ? 'Hide hidden notes' : 'Show hidden notes',
          ),
          // Favourites toggle button
          IconButton(
            icon: Icon(
              _showFavouritesOnly ? Icons.star : Icons.star_border,
              color: _showFavouritesOnly ? const Color(0xFFFFB300) : null,
            ),
            onPressed: () {
              setState(() {
                _showFavouritesOnly = !_showFavouritesOnly;
              });
            },
            tooltip: _showFavouritesOnly ? 'Show all notes' : 'Show favourites only',
          ),
          // Filter by category button (multi-select)
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: _selectedCategories.isNotEmpty ? const Color(0xFF6A1B9A) : null,
            ),
            tooltip: 'Filter by categories',
            onPressed: () => _showCategoryFilterDialog(),
          ),
          // Sort button
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (value) {
              setState(() {
                if (value == 'order') {
                  _sortOrder = _sortOrder == 'asc' ? 'desc' : 'asc';
                } else {
                  _sortBy = value;
                }
              });
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'updated',
                checked: _sortBy == 'updated',
                child: const Text('Updated'),
              ),
              CheckedPopupMenuItem(
                value: 'created',
                checked: _sortBy == 'created',
                child: const Text('Created'),
              ),
              CheckedPopupMenuItem(
                value: 'title',
                checked: _sortBy == 'title',
                child: const Text('Title'),
              ),
              CheckedPopupMenuItem(
                value: 'category',
                checked: _sortBy == 'category',
                child: const Text('Category'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'order',
                child: Text(_sortOrder == 'asc' ? 'Ascending' : 'Descending'),
              ),
            ],
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_errorMessage'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadAndSync,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _filteredAndSortedNotes.isEmpty
                  ? Center(
                      child: Text(
                        _notes.isEmpty
                            ? 'No notes yet. Tap + to create one!'
                            : 'No notes match the filter',
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Calculate number of columns based on screen width
                          final width = constraints.maxWidth;
                          final crossAxisCount = width > 1200
                              ? 6
                              : width > 900
                                  ? 4
                                  : width > 600
                                      ? 3
                                      : 2;

                          return GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: _filteredAndSortedNotes.length,
                            itemBuilder: (context, index) {
                          final note = _filteredAndSortedNotes[index];

                          // Extract plain text from Delta for preview
                          String previewText = '';
                          try {
                            final deltaJson = note.getContentAsDelta();
                            final doc = ParchmentDocument.fromJson(jsonDecode(deltaJson));
                            previewText = doc.toPlainText();
                          } catch (e) {
                            // Fallback to raw content if parsing fails
                            previewText = note.content;
                          }

                          return Card(
                            elevation: 2,
                            color: const Color(0xFFFDFDFD),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _navigateToEditNote(note),
                              onLongPress: () => _showDeleteDialog(note),
                              onSecondaryTapDown: Platform.isWindows || Platform.isLinux || Platform.isMacOS
                                  ? (details) => _showContextMenu(context, details, note)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Title with favourite star and hidden icon
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _getDisplayTitle(note),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (note.isFavourite)
                                          const Icon(
                                            Icons.star,
                                            color: Color(0xFFFFB300),
                                            size: 20,
                                          ),
                                        if (note.isHidden)
                                          const Icon(
                                            Icons.visibility_off,
                                            color: Color(0xFF6A1B9A),
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                    // Category chip
                                    if (note.category != null && note.category!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Chip(
                                        label: Text(
                                          note.category!,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        backgroundColor: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: Text(
                                        previewText,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                        maxLines: 6,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                            },
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateNote,
        backgroundColor: const Color(0xFF6A1B9A),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
          ),
        ),
      ],
    );
  }
}
