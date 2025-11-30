import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _hasUnsavedChanges = false;
  bool _isFavourite = false;
  bool _isHidden = false;
  Set<String> _availableCategories = {};

  bool get _isEditMode => widget.note != null;

  @override
  void initState() {
    super.initState();
    _loadCategories();

    // If editing, populate fields with existing note data
    if (_isEditMode) {
      _titleController.text = widget.note!.title;
      _categoryController.text = widget.note!.category ?? '';
      _isFavourite = widget.note!.isFavourite;
      _isHidden = widget.note!.isHidden;
      // Load content as Delta JSON
      try {
        final deltaJson = widget.note!.getContentAsDelta();
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

    // Listen for changes
    _titleController.addListener(_markAsUnsaved);
    _categoryController.addListener(_markAsUnsaved);
    _fleatherController.addListener(_markAsUnsaved);
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
      final updatedNote = widget.note!.copyWith(
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
    final newHiddenStatus = !_isHidden;
    setState(() {
      _isHidden = newHiddenStatus;
    });

    // Immediately save to database if editing
    if (_isEditMode) {
      try {
        final updatedNote = widget.note!.copyWith(
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update hidden status: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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

  Future<void> _saveNote() async {
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

    try {
      // TRY BACKEND FIRST
      final backendNote = await _apiService.createNote(
        _titleController.text,
        deltaJson,
        category: category,
        isFavourite: _isFavourite,
        isHidden: _isHidden,
      );

      // Backend succeeded! Save to local as already synced
      await _dbHelper.createSynced(
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
        setState(() {
          _hasUnsavedChanges = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note saved ✓')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      // Backend failed (offline or error) - save locally only
      await _dbHelper.create(
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
        Navigator.pop(context, true);
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
        content: Text('Are you sure you want to delete "${widget.note!.title}"?'),
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
      final note = widget.note!;

      // Try to delete from backend first (if note has server_id)
      if (note.serverId != null) {
        try {
          await _apiService.deleteNote(note.serverId!);
          // Backend succeeded, hard delete from local
          await _dbHelper.hardDelete(note.id!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Note deleted ✓')),
            );
            Navigator.pop(context, true);
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
            Navigator.pop(context, true);
          }
        }
      } else {
        // Note was created offline, just delete locally
        await _dbHelper.hardDelete(note.id!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note deleted ✓')),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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

    try {
      final updatedNote = widget.note!.copyWith(
        title: _titleController.text,
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
            title: _titleController.text,
            content: deltaJson,
            category: category,
            isFavourite: _isFavourite,
            isHidden: _isHidden,
          );

          // Backend succeeded! Update local with backend's timestamp
          await _dbHelper.updateFromBackend(backendNote, updatedNote.serverId!);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Note updated ✓')),
            );
            Navigator.pop(context, true);
          }
        } catch (e) {
          // Backend failed - update locally only (will sync later)
          await _dbHelper.update(updatedNote);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Updated offline - will sync when online'),
                backgroundColor: Colors.orange,
              ),
            );
            Navigator.pop(context, true);
          }
        }
      } else {
        // Note was created offline, just update locally
        await _dbHelper.update(updatedNote);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Updated offline - will sync when online'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context, true);
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
    // Set status bar color to dark for this screen
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Note' : 'New Note'),
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
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: _isSaving ? null : _saveNote,
            tooltip: 'Save',
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
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
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
                  padding: const EdgeInsets.all(16.0),
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
