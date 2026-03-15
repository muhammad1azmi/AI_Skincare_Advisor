import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Session metadata returned by the backend.
class SessionInfo {
  final String sessionId;
  final String? createTime;
  final String? lastUpdateTime;
  final String lastMessage;
  final int messageCount;

  SessionInfo({
    required this.sessionId,
    this.createTime,
    this.lastUpdateTime,
    required this.lastMessage,
    required this.messageCount,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionId: json['session_id'] as String,
      createTime: json['create_time'] as String?,
      lastUpdateTime: json['last_update_time'] as String?,
      lastMessage: json['last_message'] as String? ?? 'Consultation',
      messageCount: json['message_count'] as int? ?? 0,
    );
  }
}

/// Persisted chat message for local cache.
class CachedMessage {
  final String id;
  final String content;
  final String role;
  final String? agent;
  final String timestamp;

  CachedMessage({
    required this.id,
    required this.content,
    required this.role,
    this.agent,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'role': role,
        'agent': agent,
        'timestamp': timestamp,
      };

  factory CachedMessage.fromJson(Map<String, dynamic> json) {
    return CachedMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      role: json['role'] as String,
      agent: json['agent'] as String?,
      timestamp: json['timestamp'] as String,
    );
  }
}

/// Service for fetching session lists and caching chat messages locally.
class ChatHistoryService {
  static const String _messagesKeyPrefix = 'chat_messages_';
  static const String _sessionIdsKey = 'local_session_ids';

  // ─── Remote: fetch sessions from backend ───

  /// Fetch past sessions for a user from the backend.
  Future<List<SessionInfo>> fetchSessions({
    required String userId,
    String? authToken,
  }) async {
    try {
      final url = Uri.parse(
        '${AppConfig.restBaseUrl}/api/sessions/$userId'
        '${authToken != null ? '?token=$authToken' : ''}',
      );

      final response = await http.get(url).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final sessions = data['sessions'] as List<dynamic>? ?? [];
        return sessions
            .map((s) => SessionInfo.fromJson(s as Map<String, dynamic>))
            .toList();
      }

      debugPrint('[ChatHistory] Server returned ${response.statusCode}');
      return [];
    } catch (e) {
      debugPrint('[ChatHistory] Failed to fetch sessions: $e');
      return [];
    }
  }

  // ─── Local: message cache ───

  /// Save a message to local cache for a given session.
  Future<void> saveMessage(String sessionId, CachedMessage message) async {
    final prefs = await SharedPreferences.getInstance();

    final key = '$_messagesKeyPrefix$sessionId';
    final existing = prefs.getStringList(key) ?? [];
    existing.add(jsonEncode(message.toJson()));
    await prefs.setStringList(key, existing);

    // Also track this session ID locally.
    final sessionIds = prefs.getStringList(_sessionIdsKey) ?? [];
    if (!sessionIds.contains(sessionId)) {
      sessionIds.insert(0, sessionId);
      await prefs.setStringList(_sessionIdsKey, sessionIds);
    }
  }

  /// Load cached messages for a session.
  Future<List<CachedMessage>> loadMessages(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_messagesKeyPrefix$sessionId';
    final items = prefs.getStringList(key) ?? [];

    return items.map((json) {
      return CachedMessage.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    }).toList();
  }

  /// Get locally known session IDs (for offline fallback).
  Future<List<String>> getLocalSessionIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_sessionIdsKey) ?? [];
  }

  /// Get the last message preview for a local session.
  Future<String?> getLastMessagePreview(String sessionId) async {
    final messages = await loadMessages(sessionId);
    if (messages.isEmpty) return null;
    final last = messages.last;
    final preview =
        last.content.length > 80 ? '${last.content.substring(0, 80)}…' : last.content;
    return '${last.role == 'user' ? 'You: ' : ''}$preview';
  }
}
