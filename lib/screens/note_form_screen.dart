import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:fleather/fleather.dart';
import '../models/note.dart';
import '../services/api_service.dart';
import '../services/database_helper.dart';

class NoteFormScreen extends StatefulWidget {
  final Note? note; // If null, create mode. If not null, edit mode.

  const NoteFormScreen({super.key, this.note});

  @override
  State<NoteFormScreen> createState() => _NoteFormScreenState();
}

class _NoteFormScreenState extends State<NoteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  late FleatherController _fleatherController;
  final ApiService _apiService = ApiService.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final FocusNode _editorFocusNode = FocusNode();
  bool _isSaving = false;
  bool _isFavourite = false;
  bool _isHidden = false;
  Set<String> _availableCategories = {};
  String _statusMessage = '';
  Timer? _autoSaveTimer;
  Note? _currentNote;

  bool get _isEditMode => _currentNote != null;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    _loadCategories();

    // If editing, populate fields with existing note data
    if (_currentNote != null) {
      _titleController.text = _currentNote!.title;
      _categoryController.text = _currentNote!.category ?? '';
      _isFavourite = _currentNote!.isFavourite;
      _isHidden = _currentNote!.isHidden;
      // Load content as Delta JSON
      try {
        final deltaJson = _currentNote!.getContentAsDelta();
        final doc = ParchmentDocument.fromJson(jsonDecode(deltaJson));
        _fleatherController = FleatherController(document: doc);
      } catch (e) {
        // If parsing fails, create empty document
        _fleatherController = FleatherController();
      }
    } else {
      // Create empty document for new note
      _fleatherController = FleatherController();
    }

    // Listen for changes and trigger auto-save
    _titleController.addListener(_scheduleAutoSave);
    _categoryController.addListener(_scheduleAutoSave);
    _fleatherController.addListener(_scheduleAutoSave);
  }

  Future<void> _loadCategories() async {
    final notes = await _dbHelper.readAll();
    final categories = notes
        .where((note) => note.category != null && note.category!.isNotEmpty)
        .map((note) => note.category!)
        .toSet();
    setState(() {
      _availableCategories = categories;
    });
  }

  Future<void> _toggleFavourite() async {
    final newFavouriteStatus = !_isFavourite;
    setState(() {
      _isFavourite = newFavouriteStatus;
    });

    // Immediately save to database
    try {
      final updatedNote = _currentNote!.copyWith(
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
    final newHiddenStatus = !_isHidden;
    setState(() {
      _isHidden = newHiddenStatus;
    });

    // Immediately save to database if editing
    if (_isEditMode) {
      try {
        final updatedNote = _currentNote!.copyWith(
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
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_isSaving) {
        _saveNote();
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

  Future<void> _saveNote() async {
    _autoSaveTimer?.cancel();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    if (_isEditMode) {
      await _updateNote();
    } else {
      await _createNote();
    }
  }

  Future<void> _createNote() async {
    // Get content as Delta JSON
    final deltaJson = jsonEncode(_fleatherController.document.toDelta().toJson());
    final category = _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim();

    // Generate title from content if title is empty
    String title = _titleController.text.trim();
    if (title.isEmpty) {
      final plainText = _fleatherController.document.toPlainText().trim();
      if (plainText.isEmpty) {
        // Nothing to save - both title and content are empty
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
        return;
      }
      // Use first 50 characters of content as title
      title = plainText.length > 50
          ? '${plainText.substring(0, 50)}...'
          : plainText;
      // Remove newlines from auto-generated title
      title = title.replaceAll('\n', ' ');
    }

    try {
      // TRY BACKEND FIRST
      final backendNote = await _apiService.createNote(
        title,
        deltaJson,
        category: category,
        isFavourite: _isFavourite,
        isHidden: _isHidden,
      );

      // Backend succeeded! Save to local as already synced
      final createdNote = await _dbHelper.createSynced(
        Note(
          title: title,
          content: deltaJson,
          category: category,
          isFavourite: _isFavourite,
          isHidden: _isHidden,
          createdAt: backendNote.createdAt,
          updatedAt: backendNote.updatedAt,
        ),
        backendNote.id!,
      );

      // Switch from create mode to edit mode
      if (mounted) {
        _currentNote = createdNote;
        _showStatus('Saved');
      }
    } catch (e) {
      // Backend failed (offline or error) - save locally only
      final createdNote = await _dbHelper.create(
        Note(
          title: title,
          content: deltaJson,
          category: category,
          isFavourite: _isFavourite,
          isHidden: _isHidden,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Switch from create mode to edit mode
      if (mounted) {
        _currentNote = createdNote;
        _showStatus('Saved');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${_currentNote!.title}"?'),
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
      await _deleteNote();
    }
  }

  Future<void> _deleteNote() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final note = _currentNote!;

      // Try to delete from backend first (if note has server_id)
      if (note.serverId != null) {
        try {
          await _apiService.deleteNote(note.serverId!);
          // Backend succeeded, hard delete from local
          await _dbHelper.hardDelete(note.id!);

          if (mounted) {
            _showStatus('Deleted');
            Navigator.pop(context, true);
          }
        } catch (e) {
          // Backend failed (offline) - soft delete locally
          await _dbHelper.delete(note.id!);

          if (mounted) {
            _showStatus('Deleted');
            Navigator.pop(context, true);
          }
        }
      } else {
        // Note was created offline, just delete locally
        await _dbHelper.hardDelete(note.id!);

        if (mounted) {
          _showStatus('Deleted');
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showStatus('Failed to delete');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _updateNote() async {
    // Get content as Delta JSON
    final deltaJson = jsonEncode(_fleatherController.document.toDelta().toJson());
    final category = _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim();

    // Generate title from content if title is empty
    String title = _titleController.text.trim();
    if (title.isEmpty) {
      final plainText = _fleatherController.document.toPlainText().trim();
      if (plainText.isEmpty) {
        // Nothing to save - both title and content are empty
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
        return;
      }
      // Use first 50 characters of content as title
      title = plainText.length > 50
          ? '${plainText.substring(0, 50)}...'
          : plainText;
      // Remove newlines from auto-generated title
      title = title.replaceAll('\n', ' ');
    }

    try {
      final updatedNote = _currentNote!.copyWith(
        title: title,
        content: deltaJson,
        category: category,
        isFavourite: _isFavourite,
        isHidden: _isHidden,
        updatedAt: DateTime.now(),
      );

      // TRY BACKEND FIRST (if note has server_id)
      if (updatedNote.serverId != null) {
        try {
          final backendNote = await _apiService.updateNote(
            updatedNote.serverId!,
            title: title,
            content: deltaJson,
            category: category,
            isFavourite: _isFavourite,
            isHidden: _isHidden,
          );

          // Backend succeeded! Update local with backend's timestamp
          await _dbHelper.updateFromBackend(backendNote, updatedNote.serverId!);

          if (mounted) {
            _showStatus('Updated');
          }
        } catch (e) {
          // Backend failed - update locally only (will sync later)
          await _dbHelper.update(updatedNote);

          if (mounted) {
            _showStatus('Updated');
          }
        }
      } else {
        // Note was created offline, just update locally
        await _dbHelper.update(updatedNote);

        if (mounted) {
          _showStatus('Updated');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<bool> _onWillPop() async {
    // Save before exiting
    if (_autoSaveTimer?.isActive ?? false) {
      _autoSaveTimer?.cancel();
      await _saveNote();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Set status bar color to dark for this screen
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop(true); // Pass true to indicate note was modified
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Row(
          children: [
            Text(_isEditMode ? 'Edit Note' : 'New Note'),
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        actions: [
          if (_isEditMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _showDeleteDialog,
              tooltip: 'Delete note',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Title field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
              child: TextFormField(
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
                autofocus: !_isEditMode,
                validator: (value) {
                  // Title is now optional - will be auto-generated from content if empty
                  return null;
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
                    onPressed: _isEditMode ? () => _toggleFavourite() : () {
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
                    onPressed: _isEditMode ? () => _toggleHidden() : () {
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
            FleatherToolbar.basic(controller: _fleatherController),
            const Divider(height: 1),
            // Content editor
            Expanded(
              child: Container(
                color: const Color(0xFFF8F9FA),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    top: 16.0,
                    bottom: MediaQuery.of(context).padding.bottom + 16.0,
                  ),
                  child: FleatherEditor(
                    controller: _fleatherController,
                    focusNode: _editorFocusNode,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
