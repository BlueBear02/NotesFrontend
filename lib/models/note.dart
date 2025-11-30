import 'dart:convert';

class Note {
  final int? id;
  final int? serverId;
  final String title;
  final String content; // Stores Delta JSON as string
  final String? category;
  final bool isFavourite;
  final bool isHidden;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;

  Note({
    this.id,
    this.serverId,
    required this.title,
    required this.content,
    this.category,
    this.isFavourite = false,
    this.isHidden = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = 'synced',
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Helper: Check if content is Delta JSON format
  bool get isDeltaFormat {
    try {
      final decoded = jsonDecode(content);
      return decoded is List && decoded.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Helper: Convert plain text to Delta JSON format
  static String plainTextToDelta(String plainText) {
    return jsonEncode([
      {'insert': plainText}
    ]);
  }

  // Helper: Get content as Delta JSON (convert if needed)
  String getContentAsDelta() {
    if (isDeltaFormat) {
      return content;
    }
    // Legacy plain text - convert to Delta
    return plainTextToDelta(content);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'title': title,
      'content': content,
      'category': category,
      'is_favourite': isFavourite ? 1 : 0,
      'is_hidden': isHidden ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int?,
      serverId: map['server_id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      category: map['category'] as String?,
      isFavourite: map['is_favourite'] == 1 || map['is_favourite'] == true,
      isHidden: map['is_hidden'] == 1 || map['is_hidden'] == true,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      syncStatus: map['sync_status'] as String? ?? 'synced',
    );
  }

  Note copyWith({
    int? id,
    int? serverId,
    String? title,
    String? content,
    Object? category = const _Undefined(),
    bool? isFavourite,
    bool? isHidden,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) {
    return Note(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category is _Undefined ? this.category : category as String?,
      isFavourite: isFavourite ?? this.isFavourite,
      isHidden: isHidden ?? this.isHidden,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}

// Helper class to distinguish between "not provided" and "null"
class _Undefined {
  const _Undefined();
}
