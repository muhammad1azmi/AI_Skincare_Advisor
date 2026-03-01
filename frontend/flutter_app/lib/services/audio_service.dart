import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// Audio recording service for real-time PCM streaming.
///
/// Records PCM audio (16kHz, 16-bit, mono) and provides a stream
/// of base64-encoded chunks for WebSocket transmission.
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordingSub;
  bool _isRecording = false;

  /// Whether the service is currently recording.
  bool get isRecording => _isRecording;

  /// Start recording and return a stream of base64-encoded PCM chunks.
  Stream<String> startRecording() {
    final controller = StreamController<String>();

    _startCapture(controller);

    return controller.stream;
  }

  Future<void> _startCapture(StreamController<String> controller) async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      controller.addError('Microphone permission denied');
      await controller.close();
      return;
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );

      _isRecording = true;

      _recordingSub = stream.listen(
        (data) {
          // Convert raw PCM bytes to base64 for WebSocket.
          final base64Chunk = base64Encode(data);
          controller.add(base64Chunk);
        },
        onError: (error) {
          debugPrint('[Audio] Recording error: $error');
          controller.addError(error);
        },
        onDone: () {
          controller.close();
        },
      );
    } catch (e) {
      debugPrint('[Audio] Failed to start recording: $e');
      controller.addError(e);
      await controller.close();
    }
  }

  /// Stop recording.
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    await _recordingSub?.cancel();
    _recordingSub = null;
    await _recorder.stop();
    debugPrint('[Audio] Recording stopped');
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stopRecording();
    _recorder.dispose();
  }
}
