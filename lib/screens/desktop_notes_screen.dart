import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:fleather/fleather.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../services/preferences_service.dart';
import '../widgets/custom_title_bar.dart';
import 'home_screen.dart';

class DesktopNotesScreen extends StatefulWidget {
  final Note? initialNote;
  final bool createNew;
  final bool showHiddenNotesInitially;

  const DesktopNotesScreen({
    super.key,
    this.initialNote,
    this.createNew = false,
    this.showHiddenNotesInitially = false,
  });

  @override
  State<DesktopNotesScreen> createState() => _DesktopNotesScreenState();
}

class _DesktopNotesScreenState extends State<DesktopNotesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final SyncService _syncService = SyncService.instance;
  final ApiService _apiService = ApiService.instance;
  final AuthService _authService = AuthService.instance;
  final PreferencesService _prefsService = PreferencesService.instance;

  List<Note> _notes = [];
  Note? _selectedNote;
  bool _isLoading = true;
  String _syncStatus = '';
  bool _isCreatingNew = false;

  // Editor controllers
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  late FleatherController _fleatherController;
  final FocusNode _editorFocusNode = FocusNode();
  bool _isSaving = false;
  bool _isFavourite = false;
  bool _isHidden = false;
  bool _showHiddenNotes = false;
  Set<String> _availableCategories = {};
  String _statusMessage = '';
  Timer? _autoSaveTimer;
  bool _isFullscreen = false;
  String _lastSavedContent = '';
  String _lastSavedTitle = '';
  String? _lastSavedCategory;

  // Sidebar width
  double _sidebarWidth = 250;
  final double _minSidebarWidth = 200;
  final double _maxSidebarWidth = 400;

  // Filter and sort
  Set<String> _selectedCategories = {}; // Multi-select: empty = show all
  String _sortBy = 'updated'; // 'created', 'updated', 'category', 'title'
  String _sortOrder = 'desc'; // 'asc' or 'desc'
  bool _showFavouritesOnly = false;
  final _expandedCategories = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _fleatherController = FleatherController();

    // Initialize showHiddenNotes based on parameter
    _showHiddenNotes = widget.showHiddenNotesInitially;

    // Listen for changes and trigger auto-save
    _titleController.addListener(_scheduleAutoSave);
    _categoryController.addListener(_scheduleAutoSave);
    _fleatherController.addListener(_scheduleAutoSave);

    _loadSelectedCategories().then((_) {
      _loadNotesFromLocal().then((_) {
        _extractCategories();
        // If an initial note was passed, select it
        if (widget.initialNote != null) {
          final matchingNote = _notes.firstWhere(
            (note) => note.id == widget.initialNote!.id,
            orElse: () => widget.initialNote!,
          );
          _selectNote(matchingNote);
        } else if (widget.createNew) {
          // If createNew flag is set, automatically start creating a new note
          _createNewNote();
        }
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
      // Initialize all categories as expanded
      for (final category in categories) {
        _expandedCategories.putIfAbsent(category, () => true);
      }
      _expandedCategories.putIfAbsent('Uncategorized', () => true);
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

  Map<String, List<Note>> get _groupedNotes {
    final grouped = <String, List<Note>>{};
    final filtered = _filteredAndSortedNotes;

    for (final note in filtered) {
      final category = note.category ?? 'Uncategorized';
      grouped.putIfAbsent(category, () => []).add(note);
    }

    return grouped;
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_isSaving && (_selectedNote != null || _isCreatingNew)) {
        _saveCurrentNote();
      }
    });
  }

  void _showStatus(String message, {Duration duration = const Duration(seconds: 2)}) {
    setState(() {
      _statusMessage = message;
    });
    Future.delayed(duration, () {
      if (mounted) {
        setState(() {
          _statusMessage = '';
        });
      }
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _categoryController.dispose();
    _fleatherController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  Future<void> _syncInBackground() async {
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

  Future<void> _loadNotesFromLocal() async {
    setState(() {
      _isLoading = true;
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
        _isLoading = false;
      });
    }
  }

  Future<void> _selectNote(Note note) async {
    // Save current note before switching
    if (_autoSaveTimer?.isActive ?? false) {
      _autoSaveTimer?.cancel();
      await _saveCurrentNote();
    }

    // Save this as the last opened note
    if (note.id != null) {
      await _prefsService.setLastOpenedNoteId(note.id!);
    }

    // Remove listeners temporarily
    _titleController.removeListener(_scheduleAutoSave);
    _categoryController.removeListener(_scheduleAutoSave);

    setState(() {
      _selectedNote = note;
      _isCreatingNew = false;
      _titleController.text = note.title;
      _categoryController.text = note.category ?? '';
      _isFavourite = note.isFavourite;
      _isHidden = note.isHidden;

      // Store last saved state
      _lastSavedTitle = note.title;
      _lastSavedCategory = note.category;

      // Load content as Delta JSON
      try {
        final deltaJson = note.getContentAsDelta();
        _lastSavedContent = deltaJson;
        final doc = ParchmentDocument.fromJson(jsonDecode(deltaJson));
        _fleatherController.dispose();
        _fleatherController = FleatherController(document: doc);
        _fleatherController.addListener(_scheduleAutoSave);
      } catch (e) {
        _fleatherController.dispose();
        _fleatherController = FleatherController();
        _fleatherController.addListener(_scheduleAutoSave);
        _lastSavedContent = jsonEncode(_fleatherController.document.toDelta().toJson());
      }
    });

    // Re-add listeners
    _titleController.addListener(_scheduleAutoSave);
    _categoryController.addListener(_scheduleAutoSave);
  }

  Future<void> _createNewNote() async {
    // Save current note before creating new
    if (_autoSaveTimer?.isActive ?? false) {
      _autoSaveTimer?.cancel();
      await _saveCurrentNote();
    }

    // Remove listeners temporarily
    _titleController.removeListener(_scheduleAutoSave);
    _categoryController.removeListener(_scheduleAutoSave);

    setState(() {
      _selectedNote = null;
      _isCreatingNew = true;
      _titleController.clear();
      _categoryController.clear();
      _isFavourite = false;
      _isHidden = false;
      _fleatherController.dispose();
      _fleatherController = FleatherController();
      _fleatherController.addListener(_scheduleAutoSave);

      // Reset last saved state
      _lastSavedTitle = '';
      _lastSavedCategory = null;
      _lastSavedContent = '';
    });

    // Re-add listeners
    _titleController.addListener(_scheduleAutoSave);
    _categoryController.addListener(_scheduleAutoSave);
  }

  Future<void> _saveCurrentNote() async {
    _autoSaveTimer?.cancel();

    // Check if anything actually changed
    final currentContent = jsonEncode(_fleatherController.document.toDelta().toJson());

    // Generate title from content if title is empty
    String currentTitle = _titleController.text.trim();
    if (currentTitle.isEmpty) {
      final plainText = _fleatherController.document.toPlainText().trim();
      if (plainText.isEmpty) {
        return; // Nothing to save - both title and content are empty
      }
      // Use first 50 characters of content as title
      currentTitle = plainText.length > 50
          ? '${plainText.substring(0, 50)}...'
          : plainText;
      // Remove newlines from auto-generated title
      currentTitle = currentTitle.replaceAll('\n', ' ');
    }

    final currentCategory = _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim();

    if (currentContent == _lastSavedContent &&
        currentTitle == _lastSavedTitle &&
        currentCategory == _lastSavedCategory) {
      return; // Nothing changed, skip save
    }

    setState(() {
      _isSaving = true;
    });

    final deltaJson = currentContent;

    try {
      if (_selectedNote == null) {
        // Create new note
        final createdNote = await _createNote(deltaJson);
        // Select the newly created note
        if (createdNote != null) {
          setState(() {
            _selectedNote = createdNote;
            _isCreatingNew = false;
          });
        }
      } else {
        // Update existing note
        await _updateNote(deltaJson);
      }

      // Update last saved state
      _lastSavedContent = currentContent;
      _lastSavedTitle = currentTitle;
      _lastSavedCategory = currentCategory;

    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<Note?> _createNote(String deltaJson) async {
    final category = _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim();
    Note? createdNote;

    try {
      final backendNote = await _apiService.createNote(
        _titleController.text,
        deltaJson,
        category: category,
        isFavourite: _isFavourite,
        isHidden: _isHidden,
      );

      createdNote = await _dbHelper.createSynced(
        Note(
          title: _titleController.text,
          content: deltaJson,
          category: category,
          isFavourite: _isFavourite,
          isHidden: _isHidden,
          createdAt: backendNote.createdAt,
          updatedAt: backendNote.updatedAt,
        ),
        backendNote.id!,
      );

      if (mounted) {
        _showStatus('Saved');
        // Add to local list without reloading
        _notes.add(createdNote);
        _extractCategories();
        setState(() {});
      }
    } catch (e) {
      createdNote = await _dbHelper.create(
        Note(
          title: _titleController.text,
          content: deltaJson,
          category: category,
          isFavourite: _isFavourite,
          isHidden: _isHidden,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      if (mounted) {
        _showStatus('Saved');
        // Add to local list without reloading
        _notes.add(createdNote);
        _extractCategories();
        setState(() {});
      }
    }

    return createdNote;
  }

  Future<void> _updateNote(String deltaJson) async {
    final category = _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim();

    try {
      final updatedNote = _selectedNote!.copyWith(
        title: _titleController.text,
        content: deltaJson,
        category: category,
        isFavourite: _isFavourite,
        isHidden: _isHidden,
        updatedAt: DateTime.now(),
      );

      if (updatedNote.serverId != null) {
        try {
          final backendNote = await _apiService.updateNote(
            updatedNote.serverId!,
            title: _titleController.text,
            content: deltaJson,
            category: category,
            isFavourite: _isFavourite,
            isHidden: _isHidden,
          );

          await _dbHelper.updateFromBackend(backendNote, updatedNote.serverId!);

          if (mounted) {
            _showStatus('Updated');
          }
        } catch (e) {
          await _dbHelper.update(updatedNote);

          if (mounted) {
            _showStatus('Updated');
          }
        }
      } else {
        await _dbHelper.update(updatedNote);

        if (mounted) {
          _showStatus('Updated');
        }
      }

      // Update in local list without reloading
      if (mounted) {
        final index = _notes.indexWhere((n) => n.id == updatedNote.id);
        if (index != -1) {
          _notes[index] = updatedNote;
          setState(() {});
        }
        _selectedNote = updatedNote;
      }
    } catch (e) {
      if (mounted) {
        _showStatus('Failed to save');
      }
    }
  }

  Future<void> _deleteNote(Note note) async {
    try {
      if (note.serverId != null) {
        try {
          await _apiService.deleteNote(note.serverId!);
          await _dbHelper.hardDelete(note.id!);

          if (mounted) {
            _showStatus('Deleted');
          }
        } catch (e) {
          await _dbHelper.delete(note.id!);

          if (mounted) {
            _showStatus('Deleted');
          }
        }
      } else {
        await _dbHelper.hardDelete(note.id!);

        if (mounted) {
          _showStatus('Deleted');
        }
      }

      setState(() {
        _selectedNote = null;
        _titleController.clear();
        _fleatherController = FleatherController();
      });

      await _loadNotesFromLocal();
    } catch (e) {
      if (mounted) {
        _showStatus('Failed to delete');
      }
    }
  }

  void _showDeleteContextMenu(BuildContext context, TapDownDetails details, Note note) {
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
          child: Row(
            children: [
              Icon(Icons.folder, color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              const Text('Move to category'),
            ],
          ),
          onTap: () {
            _showMoveToCategoryDialog(note);
          },
        ),
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

  Future<void> _showMoveToCategoryDialog(Note note) async {
    final TextEditingController newCategoryController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to category'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Existing categories
              ..._availableCategories.map((category) => ListTile(
                leading: Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
                title: Text(category),
                trailing: note.category == category
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _moveNoteToCategory(note, category);
                },
              )),
              const Divider(),
              // Remove category
              ListTile(
                leading: const Icon(Icons.folder_off, color: Colors.grey),
                title: const Text('Remove category'),
                onTap: () {
                  Navigator.pop(context);
                  _moveNoteToCategory(note, null);
                },
              ),
              const Divider(),
              // New category
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: newCategoryController,
                  decoration: const InputDecoration(
                    labelText: 'New category',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.add),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.pop(context);
                      _moveNoteToCategory(note, value.trim());
                    }
                  },
                ),
              ),
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
              if (newCategoryController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _moveNoteToCategory(note, newCategoryController.text.trim());
              }
            },
            child: const Text('Create & Move'),
          ),
        ],
      ),
    );

    newCategoryController.dispose();
  }

  Future<void> _moveNoteToCategory(Note note, String? category) async {
    try {
      final updatedNote = note.copyWith(
        category: category,
        updatedAt: DateTime.now(),
      );

      // Always update local database first
      await _dbHelper.update(updatedNote);

      // Try to sync with backend
      if (updatedNote.serverId != null) {
        try {
          await _apiService.updateNote(
            updatedNote.serverId!,
            category: category,
          );

          if (mounted) {
            _showStatus(category == null ? 'Category removed' : 'Moved');
          }
        } catch (e) {
          if (mounted) {
            _showStatus('Updated');
          }
        }
      } else {
        if (mounted) {
          _showStatus(category == null ? 'Category removed' : 'Moved');
        }
      }

      await _loadNotesFromLocal();

      // Force UI rebuild
      if (mounted) {
        setState(() {
          // If this was the selected note, refresh it from the updated list
          if (_selectedNote?.id == note.id) {
            final refreshedNote = _notes.firstWhere(
              (n) => n.id == note.id,
              orElse: () => updatedNote,
            );
            _selectedNote = refreshedNote;
            _categoryController.text = refreshedNote.category ?? '';
            _isFavourite = refreshedNote.isFavourite;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showStatus('Failed to move');
      }
    }
  }

  Future<void> _toggleFavourite() async {
    if (_selectedNote == null) return;

    final newFavouriteStatus = !_isFavourite;
    setState(() {
      _isFavourite = newFavouriteStatus;
    });

    // Immediately save to database
    try {
      final updatedNote = _selectedNote!.copyWith(
        isFavourite: newFavouriteStatus,
        updatedAt: DateTime.now(),
      );

      if (updatedNote.serverId != null) {
        try {
          await _apiService.updateNote(
            updatedNote.serverId!,
            isFavourite: newFavouriteStatus,
          );
          await _dbHelper.updateFromBackend(
            updatedNote.copyWith(updatedAt: DateTime.now()),
            updatedNote.serverId!,
          );
        } catch (e) {
          // Backend failed - update locally only
          await _dbHelper.update(updatedNote);
        }
      } else {
        await _dbHelper.update(updatedNote);
      }

      await _loadNotesFromLocal();

      // Update selected note reference
      _selectedNote = updatedNote;
    } catch (e) {
      // Revert on error
      setState(() {
        _isFavourite = !newFavouriteStatus;
      });
      if (mounted) {
        _showStatus('Failed to update');
      }
    }
  }

  Future<void> _toggleHidden() async {
    if (_selectedNote == null) return;

    final newHiddenStatus = !_isHidden;
    setState(() {
      _isHidden = newHiddenStatus;
    });

    // Immediately save to database
    try {
      final updatedNote = _selectedNote!.copyWith(
        isHidden: newHiddenStatus,
        updatedAt: DateTime.now(),
      );

      if (updatedNote.serverId != null) {
        try {
          await _apiService.updateNote(
            updatedNote.serverId!,
            isHidden: newHiddenStatus,
          );
          await _dbHelper.updateFromBackend(
            updatedNote.copyWith(updatedAt: DateTime.now()),
            updatedNote.serverId!,
          );
        } catch (e) {
          // Backend failed - update locally only
          await _dbHelper.update(updatedNote);
        }
      } else {
        await _dbHelper.update(updatedNote);
      }

      await _loadNotesFromLocal();

      // Update selected note reference
      _selectedNote = updatedNote;

      // Check if the note still matches the current filter
      // If showing hidden notes and note is now not hidden, deselect it
      // If showing non-hidden notes and note is now hidden, deselect it
      if ((_showHiddenNotes && !newHiddenStatus) || (!_showHiddenNotes && newHiddenStatus)) {
        setState(() {
          _selectedNote = null;
          _isCreatingNew = false;
        });
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _isHidden = !newHiddenStatus;
      });
      if (mounted) {
        _showStatus('Failed to update');
      }
    }
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
          // If current note is not hidden, deselect it
          if (_selectedNote != null && !_selectedNote!.isHidden) {
            _selectedNote = null;
            _isCreatingNew = false;
          }
        });
        _extractCategories();
      } else {
        if (mounted) {
          _showStatus('Authentication failed');
        }
      }
    } else {
      // Hiding hidden notes again - no auth needed
      setState(() {
        _showHiddenNotes = false;
        // If current note is hidden, deselect it
        if (_selectedNote != null && _selectedNote!.isHidden) {
          _selectedNote = null;
          _isCreatingNew = false;
        }
      });
      _extractCategories();
    }
  }

  Future<bool> _onWillPop() async {
    // Save before exiting
    if (_autoSaveTimer?.isActive ?? false) {
      _autoSaveTimer?.cancel();
      await _saveCurrentNote();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CustomTitleBar(),
        Expanded(
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              // Exit fullscreen on ESC key
              if (event.logicalKey.keyLabel == 'Escape' && _isFullscreen) {
                setState(() {
                  _isFullscreen = false;
                });
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: PopScope<bool>(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;

                final shouldPop = await _onWillPop();
                if (shouldPop && context.mounted) {
                  Navigator.of(context).pop(_showHiddenNotes);
                }
              },
              child: Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // If fullscreen, exit fullscreen first
            if (_isFullscreen) {
              setState(() {
                _isFullscreen = false;
              });
            } else {
              // Otherwise exit the screen
              _onWillPop().then((shouldPop) {
                if (shouldPop && context.mounted) {
                  // Check if we can pop (i.e., there's a previous screen)
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop(_showHiddenNotes);
                  } else {
                    // No previous screen, navigate to home screen grid
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                    );
                  }
                }
              });
            }
          },
        ),
        title: Row(
          children: [
            Text(_isFullscreen ? (_selectedNote?.title ?? 'Note') : 'Notes'),
            if (_syncStatus.isNotEmpty && !_isFullscreen) ...[
              const SizedBox(width: 8),
              Text(
                _syncStatus,
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          if (!_isFullscreen) ...[
            IconButton(
              icon: Icon(_showHiddenNotes ? Icons.visibility_off : Icons.visibility),
              onPressed: _toggleShowHiddenNotes,
              tooltip: _showHiddenNotes ? 'Hide hidden notes' : 'Show hidden notes',
            ),
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
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _createNewNote,
              tooltip: 'New Note',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isFullscreen
              ? _buildFullscreenEditor()
              : Row(
              children: [
                // Sidebar - Notes List
                Container(
                  width: _sidebarWidth,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                      right: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
                    ),
                  ),
                  child: _notes.isEmpty
                      ? Center(
                          child: Text('No notes yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        )
                      : Column(
                          children: [
                            // Filter and Sort Controls
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerLow,
                                border: Border(
                                  bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _selectedCategories.isNotEmpty ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _selectedCategories.isNotEmpty ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: _showCategoryFilterDialog,
                                        child: Row(
                                          children: [
                                            Icon(Icons.filter_list, size: 18, color: Theme.of(context).colorScheme.onSurface),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _selectedCategories.isEmpty
                                                    ? 'All Categories'
                                                    : '${_selectedCategories.length} selected',
                                                style: TextStyle(
                                                  color: _selectedCategories.isNotEmpty ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                                                  fontWeight: _selectedCategories.isNotEmpty ? FontWeight.w500 : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                                    ),
                                    child: PopupMenuButton<String>(
                                      icon: Icon(Icons.sort, size: 20, color: Theme.of(context).colorScheme.onSurface),
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
                                          child: Row(
                                            children: [
                                              Icon(_sortOrder == 'asc' ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                                              const SizedBox(width: 8),
                                              Text(_sortOrder == 'asc' ? 'Ascending' : 'Descending'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Grouped Notes List
                            Expanded(
                              child: _groupedNotes.isEmpty
                                  ? const Center(child: Text('No notes match the filter'))
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      itemCount: _groupedNotes.entries.length,
                                      itemBuilder: (context, index) {
                                        final entry = _groupedNotes.entries.elementAt(index);
                                        final category = entry.key;
                                        final notes = entry.value;
                                        final isExpanded = _expandedCategories[category] ?? true;

                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 4.0),
                                          child: Theme(
                                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                            child: ExpansionTile(
                                              key: Key(category),
                                              initiallyExpanded: isExpanded,
                                              onExpansionChanged: (expanded) {
                                                setState(() {
                                                  _expandedCategories[category] = expanded;
                                                });
                                              },
                                              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                              childrenPadding: const EdgeInsets.only(bottom: 4),
                                              leading: Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  category == 'Uncategorized' ? Icons.folder_open : Icons.folder,
                                                  color: Theme.of(context).colorScheme.primary,
                                                  size: 20,
                                                ),
                                              ),
                                              title: Text(
                                                category,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              subtitle: Text(
                                                '${notes.length} note${notes.length == 1 ? '' : 's'}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              children: notes.map((note) {
                                                final isSelected = _selectedNote?.id == note.id;

                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                                  child: MouseRegion(
                                                    cursor: SystemMouseCursors.click,
                                                    child: GestureDetector(
                                                      onSecondaryTapDown: (details) =>
                                                          _showDeleteContextMenu(context, details, note),
                                                      child: Container(
                                                        margin: const EdgeInsets.only(left: 8, bottom: 2),
                                                        decoration: BoxDecoration(
                                                          color: isSelected
                                                              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                                                              : Colors.transparent,
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                                                                : Colors.transparent,
                                                            width: 1,
                                                          ),
                                                        ),
                                                        child: ListTile(
                                                          dense: true,
                                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                                          leading: note.isFavourite
                                                              ? const Icon(Icons.star, color: Color(0xFFFFB300), size: 18)
                                                              : note.isHidden
                                                                  ? Icon(Icons.visibility_off, color: Theme.of(context).colorScheme.primary, size: 18)
                                                                  : null,
                                                          title: Text(
                                                            _getDisplayTitle(note),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                                            ),
                                                          ),
                                                          onTap: () => _selectNote(note),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                ),
                // Resizable Divider
                GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _sidebarWidth = (_sidebarWidth + details.delta.dx)
                          .clamp(_minSidebarWidth, _maxSidebarWidth);
                    });
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: Container(
                      width: 4,
                      color: Colors.grey[300],
                      child: Center(
                        child: Container(
                          width: 1,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                  ),
                ),
                // Editor Area
                Expanded(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: _selectedNote == null && !_isCreatingNew
                        ? Center(
                            child: Text(
                              'Select a note or create a new one',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                            ),
                          )
                        : Column(
                          children: [
                            // Title field
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                              child: TextField(
                                controller: _titleController,
                                decoration: const InputDecoration(
                                  hintText: 'Title',
                                  border: InputBorder.none,
                                  hintStyle: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                                onChanged: (_) {
                                  // Auto-save could be added here
                                },
                              ),
                            ),
                            // Category and Favourite row
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _categoryController,
                                      decoration: InputDecoration(
                                        hintText: 'Category (optional)',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        prefixIcon: Icon(Icons.folder_outlined, color: Theme.of(context).colorScheme.primary),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        suffixIcon: _availableCategories.isNotEmpty
                                            ? PopupMenuButton<String>(
                                                icon: const Icon(Icons.arrow_drop_down),
                                                tooltip: 'Select category',
                                                onSelected: (category) {
                                                  _categoryController.text = category;
                                                },
                                                itemBuilder: (context) => _availableCategories
                                                    .map((cat) => PopupMenuItem(
                                                          value: cat,
                                                          child: Text(cat),
                                                        ))
                                                    .toList(),
                                              )
                                            : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    icon: Icon(
                                      _isFavourite ? Icons.star : Icons.star_border,
                                      color: _isFavourite ? const Color(0xFFFFB300) : Colors.grey,
                                      size: 28,
                                    ),
                                    onPressed: _selectedNote != null ? () => _toggleFavourite() : () {
                                      setState(() {
                                        _isFavourite = !_isFavourite;
                                      });
                                    },
                                    tooltip: _isFavourite ? 'Remove from favourites' : 'Add to favourites',
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isHidden ? Icons.visibility_off : Icons.visibility,
                                      color: _isHidden ? Theme.of(context).colorScheme.primary : Colors.grey,
                                      size: 28,
                                    ),
                                    onPressed: _selectedNote != null ? () => _toggleHidden() : () {
                                      setState(() {
                                        _isHidden = !_isHidden;
                                      });
                                    },
                                    tooltip: _isHidden ? 'Unhide note' : 'Hide note',
                                  ),
                                  const Spacer(),
                                  if (_selectedNote != null)
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 28),
                                      onPressed: () => _deleteNote(_selectedNote!),
                                      tooltip: 'Delete note',
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.fullscreen, size: 28),
                                    onPressed: () {
                                      setState(() {
                                        _isFullscreen = true;
                                      });
                                    },
                                    tooltip: 'Fullscreen (ESC to exit)',
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            // Formatting toolbar
                            SizedBox(
                              height: 56,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  IntrinsicWidth(
                                    child: FleatherToolbar.basic(controller: _fleatherController),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            // Content editor
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Builder(
                                  builder: (context) {
                                    try {
                                      return FleatherEditor(
                                        controller: _fleatherController,
                                        focusNode: _editorFocusNode,
                                        padding: EdgeInsets.zero,
                                      );
                                    } catch (e) {
                                      // Catch Fleather rendering errors and continue
                                      return FleatherEditor(
                                        controller: _fleatherController,
                                        focusNode: _editorFocusNode,
                                        padding: EdgeInsets.zero,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                  ),
                ),
              ],
            ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenEditor() {
    return Column(
      children: [
        // Formatting toolbar
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
            ),
          ),
          child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                IntrinsicWidth(
                  child: FleatherToolbar.basic(controller: _fleatherController),
                ),
              ],
            ),
          ),
        ),
        // Fullscreen editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Builder(
              builder: (context) {
                try {
                  return FleatherEditor(
                    controller: _fleatherController,
                    focusNode: _editorFocusNode,
                    padding: EdgeInsets.zero,
                  );
                } catch (e) {
                  return FleatherEditor(
                    controller: _fleatherController,
                    focusNode: _editorFocusNode,
                    padding: EdgeInsets.zero,
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
