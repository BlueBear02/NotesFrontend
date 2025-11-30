import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/note.dart';

class ApiService {
  static String get baseUrl => dotenv.env['API_URL'] ?? '';
  static String get apiKey => dotenv.env['API_KEY'] ?? '';

  static final ApiService instance = ApiService._init();

  ApiService._init();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-API-Key': ApiService.apiKey,
      };

  Future<List<Note>> getNotes({
    int skip = 0,
    int limit = 100,
    String? category,
    bool? isFavourite,
    String? sortBy,
    String? sortOrder,
  }) async {
    final queryParams = {
      'skip': skip.toString(),
      'limit': limit.toString(),
      if (category != null) 'category': category,
      if (isFavourite != null) 'is_favourite': isFavourite.toString(),
      if (sortBy != null) 'sort_by': sortBy,
      if (sortOrder != null) 'sort_order': sortOrder,
    };

    final uri = Uri.parse('$baseUrl/notes').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Note.fromMap(json)).toList();
    } else if (response.statusCode == 403) {
      throw Exception('Invalid API Key');
    } else {
      throw Exception('Failed to load notes: ${response.statusCode}');
    }
  }

  Future<Note> getNote(int noteId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notes/$noteId'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return Note.fromMap(json.decode(response.body));
    } else if (response.statusCode == 404) {
      throw Exception('Note not found');
    } else if (response.statusCode == 403) {
      throw Exception('Invalid API Key');
    } else {
      throw Exception('Failed to load note: ${response.statusCode}');
    }
  }

  Future<Note> createNote(
    String title,
    String content, {
    String? category,
    bool? isFavourite,
    bool? isHidden,
  }) async {
    final body = {
      'title': title,
      'content': content,
      if (category != null) 'category': category,
      if (isFavourite != null) 'is_favourite': isFavourite,
      if (isHidden != null) 'is_hidden': isHidden,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/notes'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return Note.fromMap(json.decode(response.body));
    } else if (response.statusCode == 403) {
      throw Exception('Invalid API Key');
    } else {
      throw Exception('Failed to create note: ${response.statusCode}');
    }
  }

  Future<Note> updateNote(
    int noteId, {
    String? title,
    String? content,
    String? category,
    bool? isFavourite,
    bool? isHidden,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (content != null) body['content'] = content;
    if (category != null) body['category'] = category;
    if (isFavourite != null) body['is_favourite'] = isFavourite;
    if (isHidden != null) body['is_hidden'] = isHidden;

    final response = await http.put(
      Uri.parse('$baseUrl/notes/$noteId'),
      headers: _headers,
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      return Note.fromMap(json.decode(response.body));
    } else if (response.statusCode == 404) {
      throw Exception('Note not found');
    } else if (response.statusCode == 403) {
      throw Exception('Invalid API Key');
    } else {
      throw Exception('Failed to update note: ${response.statusCode}');
    }
  }

  Future<void> deleteNote(int noteId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/notes/$noteId'),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw Exception('Note not found');
    } else if (response.statusCode == 403) {
      throw Exception('Invalid API Key');
    } else if (response.statusCode != 200) {
      throw Exception('Failed to delete note: ${response.statusCode}');
    }
  }
}
