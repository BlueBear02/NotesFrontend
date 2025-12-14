import 'api_service.dart';
import 'database_helper.dart';

class SyncResult {
  final bool success;
  final int notesPushed;
  final int notesPulled;
  final String? errorMessage;

  SyncResult({
    required this.success,
    this.notesPushed = 0,
    this.notesPulled = 0,
    this.errorMessage,
  });
}

class SyncService {
  static final SyncService instance = SyncService._init();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final ApiService _api = ApiService.instance;

  SyncService._init();

  Future<SyncResult> syncWithBackend() async {
    // Skip sync if API is not configured (local-only mode)
    if (!ApiService.isConfigured) {
      return SyncResult(success: true, notesPushed: 0, notesPulled: 0);
    }

    int pushedCount = 0;
    int pulledCount = 0;

    try {
      // PHASE 1: PUSH local changes to backend
      final pendingNotes = await _db.getPendingNotes();

      for (final note in pendingNotes) {
        try {
          if (note.syncStatus == 'pending_create') {
            // Create on backend
            final backendNote = await _api.createNote(note.title, note.content);

            // Update local with server_id and mark as synced
            await _db.markSynced(note.id!, backendNote.id!);
            pushedCount++;
          } else if (note.syncStatus == 'pending_update') {
            // Update on backend
            final backendNote = await _api.updateNote(
              note.serverId!,
              title: note.title,
              content: note.content,
            );

            // Update local with backend's updated_at and mark as synced
            await _db.updateFromBackend(backendNote, note.serverId!);
            pushedCount++;
          } else if (note.syncStatus == 'pending_delete') {
            // Delete on backend
            await _api.deleteNote(note.serverId!);

            // Remove from local DB
            await _db.hardDelete(note.id!);
            pushedCount++;
          }
        } catch (e) {
          // Failed to push this note, skip and try next sync
          continue;
        }
      }

      // PHASE 2: PULL backend notes and update local
      final backendNotes = await _api.getNotes().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Backend fetch timeout');
        },
      );

      // Get all backend note IDs for comparison
      final backendNoteIds = backendNotes.map((n) => n.id!).toSet();

      for (final backendNote in backendNotes) {
        final localNote = await _db.findByServerId(backendNote.id!);

        if (localNote == null) {
          // New note from backend, doesn't exist locally
          await _db.insertFromBackend(backendNote, backendNote.id!);
          pulledCount++;
        } else if (localNote.syncStatus == 'synced') {
          // Note exists locally and has no pending changes
          // Check if backend is newer using timestamp comparison
          if (backendNote.updatedAt.isAfter(localNote.updatedAt)) {
            // Backend is newer, update local
            await _db.updateFromBackend(backendNote, backendNote.id!);
            pulledCount++;
          }
          // else: Local is up to date, skip
        } else {
          // localNote.syncStatus is 'pending_update' or 'pending_delete'
          // User has unsaved local changes, DON'T overwrite
          // Will push on next sync
          continue;
        }
      }

      // PHASE 3: Delete local notes that don't exist on backend anymore
      final allLocalNotes = await _db.readAll();
      for (final localNote in allLocalNotes) {
        // Only check synced notes with server_id
        if (localNote.serverId != null && localNote.syncStatus == 'synced') {
          // If this note doesn't exist on backend, delete it locally
          if (!backendNoteIds.contains(localNote.serverId)) {
            await _db.hardDelete(localNote.id!);
            pulledCount++;
          }
        }
      }

      return SyncResult(
        success: true,
        notesPushed: pushedCount,
        notesPulled: pulledCount,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }
}
