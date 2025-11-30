import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('notes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Use appropriate directory based on platform
    String dbPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // For desktop, use application documents directory
      final appDocDir = await getApplicationDocumentsDirectory();
      dbPath = join(appDocDir.path, 'Notepad+++');
      // Create the directory if it doesn't exist
      await Directory(dbPath).create(recursive: true);
    } else {
      // For mobile, use the default database path
      dbPath = await getDatabasesPath();
    }

    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        category TEXT,
        is_favourite INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT DEFAULT 'synced'
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add new columns
      await db.execute('ALTER TABLE notes ADD COLUMN server_id INTEGER');
      await db.execute('ALTER TABLE notes ADD COLUMN sync_status TEXT DEFAULT \'synced\'');

      // For existing notes, assume they are synced
      // Set server_id = id for existing notes (they came from backend originally)
      await db.execute('UPDATE notes SET server_id = id WHERE server_id IS NULL');
      await db.execute('UPDATE notes SET sync_status = \'synced\' WHERE sync_status IS NULL');
    }

    if (oldVersion < 3) {
      // Fix any corrupt data from v2 -> v3
      // Clear any duplicate server_ids
      await db.execute('UPDATE notes SET server_id = NULL WHERE sync_status = \'pending_create\'');
    }

    if (oldVersion < 4) {
      // Add category and is_favourite columns
      await db.execute('ALTER TABLE notes ADD COLUMN category TEXT');
      await db.execute('ALTER TABLE notes ADD COLUMN is_favourite INTEGER DEFAULT 0');
    }

    if (oldVersion < 5) {
      // Add is_hidden column
      await db.execute('ALTER TABLE notes ADD COLUMN is_hidden INTEGER DEFAULT 0');
    }
  }

  Future<Note> create(Note note) async {
    final db = await database;
    final noteData = note.copyWith(
      syncStatus: 'pending_create',
      serverId: null,
    ).toMap();
    final id = await db.insert('notes', noteData);
    return note.copyWith(
      id: id,
      syncStatus: 'pending_create',
      serverId: null,
    );
  }

  Future<Note?> read(int id) async {
    final db = await database;
    final maps = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Note.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Note>> readAll() async {
    final db = await database;
    final result = await db.query(
      'notes',
      where: 'sync_status != ?',
      whereArgs: ['pending_delete'],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => Note.fromMap(map)).toList();
  }

  Future<int> update(Note note) async {
    final db = await database;
    return db.update(
      'notes',
      note.copyWith(
        updatedAt: DateTime.now(),
        syncStatus: 'pending_update',
      ).toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await database;
    // Soft delete - mark as pending_delete
    return await db.update(
      'notes',
      {'sync_status': 'pending_delete'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Sync-specific methods

  Future<List<Note>> getPendingNotes() async {
    final db = await database;
    final result = await db.query(
      'notes',
      where: 'sync_status != ?',
      whereArgs: ['synced'],
    );
    return result.map((map) => Note.fromMap(map)).toList();
  }

  Future<Note?> findByServerId(int serverId) async {
    final db = await database;
    final maps = await db.query(
      'notes',
      where: 'server_id = ?',
      whereArgs: [serverId],
    );

    if (maps.isNotEmpty) {
      return Note.fromMap(maps.first);
    }
    return null;
  }

  Future<Note> createSynced(Note note, int serverId) async {
    final db = await database;
    final noteData = note.copyWith(
      syncStatus: 'synced',
      serverId: serverId,
    ).toMap();
    final id = await db.insert('notes', noteData);
    return note.copyWith(
      id: id,
      syncStatus: 'synced',
      serverId: serverId,
    );
  }

  Future<void> markSynced(int localId, int serverId) async {
    final db = await database;
    await db.update(
      'notes',
      {
        'server_id': serverId,
        'sync_status': 'synced',
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> updateFromBackend(Note backendNote, int serverId) async {
    final db = await database;
    final localNote = await findByServerId(serverId);

    if (localNote != null) {
      await db.update(
        'notes',
        backendNote.copyWith(
          id: localNote.id,
          serverId: serverId,
          syncStatus: 'synced',
        ).toMap(),
        where: 'id = ?',
        whereArgs: [localNote.id],
      );
    }
  }

  Future<Note> insertFromBackend(Note backendNote, int serverId) async {
    final db = await database;
    final noteData = backendNote.copyWith(
      syncStatus: 'synced',
      serverId: serverId,
    ).toMap();
    final id = await db.insert('notes', noteData);
    return backendNote.copyWith(
      id: id,
      syncStatus: 'synced',
      serverId: serverId,
    );
  }

  Future<void> hardDelete(int localId) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
