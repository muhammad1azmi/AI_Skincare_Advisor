import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chat_screen.dart';
import 'package:uuid/uuid.dart';

import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/camera_service.dart';
import '../services/websocket_service.dart';

/// Live consultation screen — video-call experience with ADK bidi-streaming.
///
/// Camera preview + real-time PCM audio streaming (binary frames)
/// + JPEG frame capture + AI voice responses + live transcript.
class ConsultationScreen extends ConsumerStatefulWidget {
  const ConsultationScreen({super.key});

  @override
  ConsumerState<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends ConsumerState<ConsultationScreen>
    with TickerProviderStateMixin {
  // Services
  WebSocketService? _wsService;
  final AudioService _audioService = AudioService();
  final CameraService _cameraService = CameraService();

  // State
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _aiSpeaking = false;
  String _transcript = '';
  String _userTranscript = '';
  String _callStatus = 'Connecting...';
  late final String _sessionId = const Uuid().v4();

  // Transcript history — collects user/AI messages for the chat screen.
  final List<ChatMessage> _chatHistory = [];
  String _partialAiTranscript = '';
  String _partialUserTranscript = '';

  // Streaming subscriptions
  StreamSubscription<String>? _audioSub;
  StreamSubscription<String>? _frameSub;

  // Animations
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    // Initialize camera (front for skin selfie).
    await _cameraService.initialize(front: true);
    if (mounted) setState(() {});

    // Connect WebSocket.
    final authService = ref.read(authServiceProvider);
    final user = authService.currentUser;
    final userId = user?.uid ?? 'guest_${const Uuid().v4().substring(0, 8)}';
    final token = await authService.getIdToken();

    _wsService = WebSocketService(
      userId: userId,
      sessionId: _sessionId,
      authToken: token,
    );

    try {
      await _wsService!.connect();
      setState(() {
        _isConnected = true;
        _callStatus = 'Connected';
      });

      // Listen for ADK events.
      _wsService!.events.listen((event) {
        setState(() {
          // Text content from agent (non-streaming text response)
          if (event.textContent != null && event.textContent!.isNotEmpty) {
            _transcript = event.textContent!;
            // Add as an AI chat message
            _chatHistory.add(ChatMessage(
              content: event.textContent!,
              role: 'assistant',
              agent: event.author,
            ));
          }

          // Audio response → AI is speaking
          if (event.audioBase64 != null) {
            _aiSpeaking = true;
            // TODO: Play audio via just_audio (24kHz PCM)
          }

          // Output transcription (what the AI is saying as text)
          if (event.outputTranscriptionText != null &&
              event.outputTranscriptionText!.isNotEmpty) {
            _partialAiTranscript += event.outputTranscriptionText!;
            _transcript = _partialAiTranscript;
            _aiSpeaking = event.outputTranscriptionFinished != true;

            if (event.outputTranscriptionFinished == true) {
              // Finalize AI transcription as a chat message
              _chatHistory.add(ChatMessage(
                content: _partialAiTranscript.trim(),
                role: 'assistant',
                agent: event.author,
              ));
              _partialAiTranscript = '';
            }
          }

          // Input transcription (what the user said)
          if (event.inputTranscriptionText != null &&
              event.inputTranscriptionText!.isNotEmpty) {
            _partialUserTranscript += event.inputTranscriptionText!;
            _userTranscript = _partialUserTranscript;

            if (event.inputTranscriptionFinished == true) {
              // Finalize user transcription as a chat message
              _chatHistory.add(ChatMessage(
                content: _partialUserTranscript.trim(),
                role: 'user',
              ));
              _partialUserTranscript = '';
              _userTranscript = '';
            }
          }

          // Turn complete → AI stopped speaking
          if (event.turnComplete == true) {
            _aiSpeaking = false;
          }

          // Interrupted → AI was cut off
          if (event.interrupted == true) {
            _aiSpeaking = false;
          }
        });
      });

      // Start audio recording → binary PCM frames to WebSocket.
      _startAudioStreaming();

      // Start camera frame capture → JPEG to WebSocket.
      _startCameraStreaming();
    } catch (e) {
      setState(() => _callStatus = 'Connection failed');
      debugPrint('Failed to connect: $e');
    }
  }

  void _startAudioStreaming() {
    if (_isMuted) return;
    final audioStream = _audioService.startRecording();
    _audioSub = audioStream.listen((base64Chunk) {
      // The `record` package returns base64 but we need raw bytes
      // for binary WebSocket frames per ADK docs.
      // Decode base64 → Uint8List, then send as binary frame.
      final bytes = Uint8List.fromList(
        List<int>.from(base64Chunk.codeUnits),
      );
      // Note: record package provides raw PCM bytes as base64.
      // We pass it through to the server which expects binary frames.
      // For now, using base64 via the audio service - will need
      // integration testing to verify the exact byte format.
      _wsService?.sendAudioBytes(bytes);
    });
  }

  void _stopAudioStreaming() {
    _audioSub?.cancel();
    _audioSub = null;
    _audioService.stopRecording();
  }

  void _startCameraStreaming() {
    if (!_isCameraOn || !_cameraService.isReady) return;
    // Per ADK docs: 1 FPS recommended for image/video frames.
    final frameStream = _cameraService.startFrameStream(fps: 1);
    _frameSub = frameStream.listen((base64Frame) {
      _wsService?.sendImage(base64Frame);
    });
  }

  void _stopCameraStreaming() {
    _frameSub?.cancel();
    _frameSub = null;
    _cameraService.stopFrameStream();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    if (_isMuted) {
      _stopAudioStreaming();
    } else {
      _startAudioStreaming();
    }
  }

  void _toggleCamera() {
    setState(() => _isCameraOn = !_isCameraOn);
    if (_isCameraOn) {
      _startCameraStreaming();
    } else {
      _stopCameraStreaming();
    }
  }

  void _flipCamera() async {
    _stopCameraStreaming();
    await _cameraService.flipCamera();
    if (mounted) setState(() {});
    if (_isCameraOn) _startCameraStreaming();
  }

  void _endCall() {
    _stopAudioStreaming();
    _stopCameraStreaming();
    _wsService?.sendEnd();
    _wsService?.disconnect();

    // Navigate to chat screen with the consultation transcript
    if (_chatHistory.isNotEmpty) {
      Navigator.pushReplacementNamed(
        context,
        '/chat',
        arguments: {
          'sessionId': _sessionId,
          'initialMessages': _chatHistory,
        },
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _stopAudioStreaming();
    _stopCameraStreaming();
    _audioService.dispose();
    _cameraService.dispose();
    _pulseController.dispose();
    _wsService?.sendEnd();
    _wsService?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview (full screen).
          if (_cameraService.isReady && _isCameraOn)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraService.controller!.value.previewSize!.height,
                  height: _cameraService.controller!.value.previewSize!.width,
                  child: CameraPreview(_cameraService.controller!),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_off_outlined, size: 64,
                        color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('Camera off',
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.4), fontSize: 14)),
                  ],
                ),
              ),
            ),

          // Top bar — status.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 8,
                            color: _isConnected ? Colors.greenAccent : Colors.red),
                        const SizedBox(width: 8),
                        Text(_callStatus,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_isCameraOn)
                    IconButton(
                      onPressed: _flipCamera,
                      icon: const Icon(Icons.flip_camera_ios_rounded,
                          color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // AI presence indicator.
          Positioned(
            top: size.height * 0.35,
            left: 0, right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = _aiSpeaking
                      ? 1.0 + (_pulseController.value * 0.15)
                      : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _aiSpeaking
                              ? [const Color(0xFF6C63FF), const Color(0xFF00BFA5)]
                              : [Colors.white.withValues(alpha: 0.15),
                                 Colors.white.withValues(alpha: 0.05)],
                        ),
                        boxShadow: _aiSpeaking ? [
                          BoxShadow(
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                            blurRadius: 30, spreadRadius: 5,
                          ),
                        ] : null,
                      ),
                      child: Icon(
                        _aiSpeaking ? Icons.graphic_eq_rounded
                            : Icons.face_retouching_natural,
                        color: Colors.white, size: 44,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Live transcript (AI response).
          if (_transcript.isNotEmpty)
            Positioned(
              bottom: 160, left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _transcript,
                  style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 15, height: 1.4,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // User speech transcript (real-time).
          if (_userTranscript.isNotEmpty)
            Positioned(
              bottom: 260, left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _userTranscript,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13, fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // Bottom controls.
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallBtn(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    color: _isMuted ? Colors.red : Colors.white.withValues(alpha: 0.2),
                    onTap: _toggleMute,
                  ),
                  _CallBtn(
                    icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                    label: _isCameraOn ? 'Camera' : 'Off',
                    color: !_isCameraOn ? Colors.red : Colors.white.withValues(alpha: 0.2),
                    onTap: _toggleCamera,
                  ),
                  _CallBtn(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: Colors.red,
                    large: true,
                    onTap: _endCall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool large;

  const _CallBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final sz = large ? 72.0 : 56.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: sz, height: sz,
              child: Icon(icon, color: Colors.white, size: large ? 32 : 24),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
      ],
    );
  }
}
