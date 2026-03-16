import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// Parsed ADK event from the server.
///
/// The server forwards full ADK events via `event.model_dump_json()`.
/// This class extracts the fields relevant to the Flutter app.
class AdkEvent {
  final String? textContent;
  final String? audioBase64;
  final String? audioMimeType;
  final String? author;
  final bool? turnComplete;
  final bool? interrupted;

  // Transcription
  final String? inputTranscriptionText;
  final bool? inputTranscriptionFinished;
  final String? outputTranscriptionText;
  final bool? outputTranscriptionFinished;

  AdkEvent({
    this.textContent,
    this.audioBase64,
    this.audioMimeType,
    this.author,
    this.turnComplete,
    this.interrupted,
    this.inputTranscriptionText,
    this.inputTranscriptionFinished,
    this.outputTranscriptionText,
    this.outputTranscriptionFinished,
  });

  /// Parse a raw ADK event JSON from the server.
  factory AdkEvent.fromJson(Map<String, dynamic> json) {
    String? textContent;
    String? audioBase64;
    String? audioMimeType;

    // Parse content parts (text and audio)
    final content = json['content'] as Map<String, dynamic>?;
    if (content != null) {
      final parts = content['parts'] as List<dynamic>?;
      if (parts != null) {
        for (final part in parts) {
          final p = part as Map<String, dynamic>;
          if (p.containsKey('text')) {
            textContent = p['text'] as String?;
          } else if (p.containsKey('inlineData') || p.containsKey('inline_data')) {
            final inlineData = (p['inlineData'] ?? p['inline_data']) as Map<String, dynamic>?;
            if (inlineData != null) {
              final mime = (inlineData['mimeType'] ?? inlineData['mime_type']) as String?;
              if (mime != null && mime.startsWith('audio/')) {
                audioBase64 = inlineData['data'] as String?;
                audioMimeType = mime;
              }
            }
          }
        }
      }
    }

    // Parse transcription
    final inputTx = json['inputTranscription'] ?? json['input_transcription'];
    final outputTx = json['outputTranscription'] ?? json['output_transcription'];

    return AdkEvent(
      textContent: textContent,
      audioBase64: audioBase64,
      audioMimeType: audioMimeType,
      author: json['author'] as String?,
      turnComplete: json['turnComplete'] as bool? ?? json['turn_complete'] as bool?,
      interrupted: json['interrupted'] as bool?,
      inputTranscriptionText: inputTx != null ? (inputTx['text'] as String?) : null,
      inputTranscriptionFinished: inputTx != null ? (inputTx['finished'] as bool?) : null,
      outputTranscriptionText: outputTx != null ? (outputTx['text'] as String?) : null,
      outputTranscriptionFinished: outputTx != null ? (outputTx['finished'] as bool?) : null,
    );
  }
}

/// WebSocket service for bidi-streaming with the Cloud Run ADK backend.
///
/// Protocol (Flutter → Server):
/// - Binary frames: Raw PCM audio bytes (16kHz, 16-bit, mono)
/// - Text frames (JSON): `{"type": "text", "text": "..."}` for text
/// - Text frames (JSON): `{"type": "image", "data": "...", "mimeType": "image/jpeg"}`
/// - Text frames (JSON): `{"type": "end"}` to close session
///
/// Protocol (Server → Flutter):
/// - Binary frames: Raw PCM audio bytes (24kHz, 16-bit, mono)
/// - Text frames: ADK event JSON (transcription, text, turn_complete)
class WebSocketService {
  final String userId;
  final String sessionId;
  final String? authToken;

  WebSocketChannel? _channel;
  StreamController<AdkEvent>? _eventController;
  StreamController<Uint8List>? _audioController;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  WebSocketService({
    required this.userId,
    required this.sessionId,
    this.authToken,
  });

  /// Stream of parsed ADK events from the server (text frames).
  Stream<AdkEvent> get events =>
      _eventController?.stream ?? const Stream.empty();

  /// Stream of raw PCM audio bytes from the server (binary frames).
  Stream<Uint8List> get audioBytes =>
      _audioController?.stream ?? const Stream.empty();

  /// Whether the WebSocket is currently connected.
  bool get isConnected => _isConnected;

  /// Connect to the WebSocket endpoint.
  Future<void> connect() async {
    _eventController?.close();
    _eventController = StreamController<AdkEvent>.broadcast();
    _audioController?.close();
    _audioController = StreamController<Uint8List>.broadcast();

    var url = AppConfig.wsUrl(userId, sessionId);
    if (authToken != null) {
      url += '?token=$authToken';
    }

    debugPrint('[WS] Connecting to $url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;
      _isConnected = true;
      _reconnectAttempts = 0;
      debugPrint('[WS] Connected');

      _channel!.stream.listen(
        (message) {
          if (message is String) {
            // Text frame = ADK event JSON (transcription, text, turn_complete)
            try {
              final json = jsonDecode(message) as Map<String, dynamic>;
              final event = AdkEvent.fromJson(json);
              _eventController?.add(event);
            } catch (e) {
              debugPrint('[WS] Failed to parse event: $e');
            }
          } else if (message is List<int>) {
            // Binary frame = raw PCM audio bytes from Gemini output
            _audioController?.add(Uint8List.fromList(message));
          }
        },
        onError: (error) {
          debugPrint('[WS] Error: $error');
          _isConnected = false;
          _eventController?.addError(error);
          _attemptReconnect();
        },
        onDone: () {
          debugPrint('[WS] Connection closed');
          _isConnected = false;
          _attemptReconnect();
        },
      );
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _isConnected = false;
      rethrow;
    }
  }

  /// Send a text message to the agent (turn-by-turn via send_content).
  void sendText(String text) {
    _sendJson({'type': 'text', 'text': text});
  }

  /// Send raw PCM audio bytes as a binary WebSocket frame.
  ///
  /// Per ADK docs: audio should be sent as binary frames, not base64 JSON.
  /// Format: 16-bit PCM, 16kHz, mono.
  void sendAudioBytes(Uint8List pcmBytes) {
    if (!_isConnected || _channel == null) {
      debugPrint('[WS] Cannot send audio — not connected');
      return;
    }
    _channel!.sink.add(pcmBytes);
  }

  /// Send an image frame (base64-encoded JPEG) for visual analysis.
  ///
  /// Per ADK docs: images use send_realtime(Blob) with JPEG format.
  void sendImage(String base64Image, {String mimeType = 'image/jpeg'}) {
    _sendJson({
      'type': 'image',
      'data': base64Image,
      'mimeType': mimeType,
    });
  }

  /// Signal end of session.
  void sendEnd() {
    _sendJson({'type': 'end'});
  }

  /// Disconnect and clean up.
  void disconnect() {
    _isConnected = false;
    _reconnectAttempts = _maxReconnectAttempts; // prevent reconnect
    _channel?.sink.close();
    _channel = null;
    _eventController?.close();
    _eventController = null;
    _audioController?.close();
    _audioController = null;
    debugPrint('[WS] Disconnected');
  }

  /// Send a JSON message as a text frame.
  void _sendJson(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      debugPrint('[WS] Cannot send — not connected');
      return;
    }
    _channel!.sink.add(jsonEncode(data));
  }

  /// Attempt reconnection with exponential backoff.
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[WS] Max reconnect attempts reached');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    debugPrint('[WS] Reconnecting in ${delay.inSeconds}s '
        '(attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    Future.delayed(delay, () {
      if (!_isConnected) connect();
    });
  }
}
