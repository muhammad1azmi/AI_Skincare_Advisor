import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Camera service for skin analysis frame capture.
///
/// Provides camera preview controller and periodic JPEG frame
/// capture for streaming to the backend.
class CameraService {
  CameraController? _controller;
  Timer? _frameTimer;
  bool _isStreaming = false;
  List<CameraDescription> _cameras = [];

  /// Active camera controller (for preview widget).
  CameraController? get controller => _controller;

  /// Whether camera is initialized and ready.
  bool get isReady => _controller?.value.isInitialized ?? false;

  /// Whether frame streaming is active.
  bool get isStreaming => _isStreaming;

  /// Initialize camera (front by default for skin selfie).
  Future<void> initialize({bool front = true}) async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      debugPrint('[Camera] No cameras available');
      return;
    }

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection ==
          (front ? CameraLensDirection.front : CameraLensDirection.back),
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();
    debugPrint('[Camera] Initialized: ${camera.name}');
  }

  /// Flip between front and back camera.
  Future<void> flipCamera() async {
    if (_cameras.length < 2) return;

    final currentDirection = _controller?.description.lensDirection;
    final useFront = currentDirection != CameraLensDirection.front;

    await _controller?.dispose();
    await initialize(front: useFront);
  }

  /// Start streaming JPEG frames at the given FPS.
  ///
  /// Returns a stream of base64-encoded JPEG images.
  Stream<String> startFrameStream({int fps = 1}) {
    final controller = StreamController<String>();

    _isStreaming = true;
    final interval = Duration(milliseconds: 1000 ~/ fps);

    _frameTimer = Timer.periodic(interval, (_) async {
      if (!_isStreaming || _controller == null || !isReady) return;

      try {
        final file = await _controller!.takePicture();
        final bytes = await file.readAsBytes();
        final base64Image = base64Encode(bytes);
        controller.add(base64Image);
      } catch (e) {
        debugPrint('[Camera] Frame capture error: $e');
      }
    });

    return controller.stream;
  }

  /// Stop frame streaming.
  void stopFrameStream() {
    _isStreaming = false;
    _frameTimer?.cancel();
    _frameTimer = null;
    debugPrint('[Camera] Frame streaming stopped');
  }

  /// Take a single snapshot and return base64 JPEG.
  Future<String?> takeSnapshot() async {
    if (_controller == null || !isReady) return null;

    try {
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('[Camera] Snapshot error: $e');
      return null;
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    stopFrameStream();
    await _controller?.dispose();
    _controller = null;
  }
}
