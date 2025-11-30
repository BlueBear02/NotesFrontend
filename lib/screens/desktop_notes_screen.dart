import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:fleather/fleather.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_helper.dart';
import '../services/sync_service.dart';
import '../widgets/custom_title_bar.dart';

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
  bool _hasUnsavedChanges = false;
  bool _isFavourite = false;
  bool _isHidden = false;
  bool _showHiddenNotes = false;
  Set<String> _availableCategories = {};

  // Sidebar width
  double _sidebarWidth = 250;
  final double _minSidebarWidth = 200;
  final double _maxSidebarWidth = 400;

  // Filter and sort
  String _filterMode = 'All'; // 'All' or category name
  String _sortBy = 'updated'; // 'created', 'updated', 'category', 'title'
  String _sortOrder = 'desc'; // 'asc' or 'desc'
  bool _showFavouritesOnly = false;
  Map<String, bool> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _fleatherController = FleatherController();

    // Initialize showHiddenNotes based on parameter
    _showHiddenNotes = widget.showHiddenNotesInitially;

    // Listen for changes to mark as unsaved
    _titleController.addListener(_markAsUnsaved);
    _categoryController.addListener(_markAsUnsaved);
    _fleatherController.addListener(_markAsUnsaved);

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
  }

  void _extractCategories() {
    final categories = _notes
        .where((note) => note.category != null && note.category!.isNotEmpty)
        .map((note) => note.category!)
        .toSet();
    setState(() {
      _availableCategories = categories;
      // Initialize all categories as expanded
      for (final category in categories) {
        _expandedCategories.putIfAbsent(category, () => true);
      }
      _expandedCategories.putIfAbsent('Uncategorized', () => true);
    });
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

    // Apply category filter
    if (_filterMode != 'All') {
      filtered = filtered.where((note) => note.category == _filterMode).toList();
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

  void _markAsUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  @override
  void dispose() {
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

  void _selectNote(Note note) {
    setState(() {
      _selectedNote = note;
      _isCreatingNew = false;
      _titleController.text = note.title;
      _categoryController.text = note.category ?? '';
      _isFavourite = note.isFavourite;
      _isHidden = note.isHidden;
      _hasUnsavedChanges = false;

      // Load content as Delta JSON
      try {
        final deltaJson = note.getContentAsDelta();
        final doc = ParchmentDocument.fromJson(jsonDecode(deltaJson));
        _fleatherController.dispose();
        _fleatherController = FleatherController(document: doc);
        _fleatherController.addListener(_markAsUnsaved);
      } catch (e) {
        _fleatherController.dispose();
        _fleatherController = FleatherController();
        _fleatherController.addListener(_markAsUnsaved);
      }
    });
  }

  void _createNewNote() {
    setState(() {
      _selectedNote = null;
      _isCreatingNew = true;
      _titleController.clear();
      _categoryController.clear();
      _isFavourite = false;
      _isHidden = false;
      _hasUnsavedChanges = false;
      _fleatherController.dispose();
      _fleatherController = FleatherController();
      _fleatherController.addListener(_markAsUnsaved);
    });
  }

  Future<void> _saveCurrentNote() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final deltaJson = jsonEncode(_fleatherController.document.toDelta().toJson());

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

      // Mark as saved
      setState(() {
        _hasUnsavedChanges = false;
      });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note saved ✓')),
        );
        await _loadNotesFromLocal();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved offline - will sync when online'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadNotesFromLocal();
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Note updated ✓')),
            );
          }
        } catch (e) {
          await _dbHelper.update(updatedNote);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Updated offline - will sync when online'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        await _dbHelper.update(updatedNote);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Updated offline - will sync when online'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      await _loadNotesFromLocal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Note deleted ✓')),
            );
          }
        } catch (e) {
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
        await _dbHelper.hardDelete(note.id!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note deleted ✓')),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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
          child: const Row(
            children: [
              Icon(Icons.folder, color: Color(0xFF6A1B9A), size: 20),
              SizedBox(width: 8),
              Text('Move to category'),
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
                leading: const Icon(Icons.folder, color: Color(0xFF6A1B9A)),
                title: Text(category),
                trailing: note.category == category
                    ? const Icon(Icons.check, color: Color(0xFF6A1B9A))
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(category == null ? 'Category removed ✓' : 'Moved to $category ✓')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Updated offline - will sync when online'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(category == null ? 'Category removed ✓' : 'Moved to $category ✓')),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to move: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update favourite: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update hidden status: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        // If current note is hidden, deselect it
        if (_selectedNote != null && _selectedNote!.isHidden) {
          _selectedNote = null;
          _isCreatingNew = false;
        }
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) {
      return true; // Allow exit
    }

    // Show confirmation dialog
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. Do you want to exit without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Exit Without Saving'),
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const CustomTitleBar(),
        Expanded(
          child: PopScope<bool>(
            canPop: !_hasUnsavedChanges,
            onPopInvokedWithResult: (didPop, result) async {
              // If already popped, we can't pop again - just return
              if (didPop) return;

              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                Navigator.of(context).pop(_showHiddenNotes);
              }
            },
            child: Scaffold(
              backgroundColor: const Color(0xFFF8F9FA),
              appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (!_hasUnsavedChanges) {
              Navigator.of(context).pop(_showHiddenNotes);
            } else {
              _onWillPop().then((shouldPop) {
                if (shouldPop && context.mounted) {
                  Navigator.of(context).pop(_showHiddenNotes);
                }
              });
            }
          },
        ),
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Sidebar - Notes List
                Container(
                  width: _sidebarWidth,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: _notes.isEmpty
                      ? const Center(
                          child: Text('No notes yet'),
                        )
                      : Column(
                          children: [
                            // Filter and Sort Controls
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey[200]!),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFDFDFD),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey[300]!),
                                      ),
                                      child: DropdownButton<String>(
                                        value: _filterMode,
                                        isExpanded: true,
                                        underline: const SizedBox(),
                                        icon: const Icon(Icons.filter_list, size: 18),
                                        items: [
                                          const DropdownMenuItem(value: 'All', child: Text('All Categories')),
                                          if (_availableCategories.isNotEmpty) const DropdownMenuItem(enabled: false, value: '', child: Divider()),
                                          ..._availableCategories.map((cat) =>
                                            DropdownMenuItem(value: cat, child: Text(cat))
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value != null && value.isNotEmpty) {
                                            setState(() => _filterMode = value);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDFDFD),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: PopupMenuButton<String>(
                                      icon: const Icon(Icons.sort, size: 20),
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
                                                  color: const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  category == 'Uncategorized' ? Icons.folder_open : Icons.folder,
                                                  color: const Color(0xFF6A1B9A),
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
                                                              ? const Color(0xFF6A1B9A).withValues(alpha: 0.1)
                                                              : Colors.transparent,
                                                          borderRadius: BorderRadius.circular(8),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? const Color(0xFF6A1B9A).withValues(alpha: 0.3)
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
                                                                  ? const Icon(Icons.visibility_off, color: Color(0xFF6A1B9A), size: 18)
                                                                  : null,
                                                          title: Text(
                                                            note.title,
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
                    color: const Color(0xFFFDFDFD),
                    child: _selectedNote == null && !_isCreatingNew
                        ? const Center(
                            child: Text(
                              'Select a note or create a new one',
                              style: TextStyle(color: Colors.grey),
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
                                        prefixIcon: const Icon(Icons.folder_outlined, color: Color(0xFF6A1B9A)),
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
                                      color: _isHidden ? const Color(0xFF6A1B9A) : Colors.grey,
                                      size: 28,
                                    ),
                                    onPressed: _selectedNote != null ? () => _toggleHidden() : () {
                                      setState(() {
                                        _isHidden = !_isHidden;
                                      });
                                    },
                                    tooltip: _isHidden ? 'Unhide note' : 'Hide note',
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
                                child: FleatherEditor(
                                  controller: _fleatherController,
                                  focusNode: _editorFocusNode,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            // Save button bar
                            Container(
                              padding: const EdgeInsets.all(16.0),
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Colors.grey[300]!),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (_selectedNote != null)
                                    TextButton.icon(
                                      onPressed: () => _deleteNote(_selectedNote!),
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _isSaving ? null : _saveCurrentNote,
                                    icon: _isSaving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.check),
                                    label: Text(_selectedNote == null ? 'Create' : 'Save'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6A1B9A),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
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
      ],
    );
  }
}
