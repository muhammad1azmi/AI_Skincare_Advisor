import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'chat_screen.dart';
import 'package:uuid/uuid.dart';

import '../services/chat_history_service.dart';

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
  final ChatHistoryService _historyService = ChatHistoryService();
  final CameraService _cameraService = CameraService();
  final FlutterSoundPlayer _soundPlayer = FlutterSoundPlayer();
  bool _playerOpen = false;

  // State
  bool _isConnecting = true;
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _aiSpeaking = false;
  bool _permissionDenied = false;
  String _transcript = '';
  String _userTranscript = '';
  String _callStatus = 'Connecting...';
  late final String _sessionId = const Uuid().v4();

  // Call timer
  Timer? _callTimer;
  int _callSeconds = 0;

  // Transcript history — collects user/AI messages for the chat screen.
  final List<ChatMessage> _chatHistory = [];
  String _partialAiTranscript = '';
  String _partialUserTranscript = '';

  // Audio playback subscription for binary PCM frames
  StreamSubscription<Uint8List>? _audioByteSub;

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
    // --- Open flutter_sound player for streaming PCM playback ---
    try {
      await _soundPlayer.openPlayer();
      _playerOpen = true;
      debugPrint('[Audio] FlutterSoundPlayer opened');
    } catch (e) {
      debugPrint('[Audio] Player open error: $e');
    }

    // --- Check permissions first ---
    final micStatus = await Permission.microphone.request();
    final camStatus = await Permission.camera.request();

    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _isConnecting = false;
          _callStatus = 'Microphone permission required';
        });
      }
      return;
    }

    // Initialize camera (front for skin selfie).
    if (camStatus.isGranted) {
      await _cameraService.initialize(front: true);
      if (mounted) setState(() {});
    } else {
      // Camera denied — can still do audio-only consultation.
      if (mounted) setState(() => _isCameraOn = false);
    }

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
      if (!mounted) return;
      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _callStatus = 'Connected';
      });

      // Start call timer.
      _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _callSeconds++);
      });

      // Haptic feedback on connect.
      HapticFeedback.mediumImpact();

      // Listen for ADK events.
      _wsService!.events.listen((event) {
        setState(() {
          // Text content from agent (non-streaming text response)
          if (event.textContent != null && event.textContent!.isNotEmpty) {
            _transcript = event.textContent!;
            final msg = ChatMessage(
              content: event.textContent!,
              role: 'assistant',
              agent: event.author,
            );
            _chatHistory.add(msg);
            _persistMessage(msg);
          }

          // Audio is now received on the binary audioBytes stream,
          // not as base64 in ADK events.

          // Output transcription (what the AI is saying as text)
          if (event.outputTranscriptionText != null &&
              event.outputTranscriptionText!.isNotEmpty) {
             // Replace (not append) — API may send full accumulated text
             _partialAiTranscript = event.outputTranscriptionText!;
             _transcript = _partialAiTranscript;
            _aiSpeaking = event.outputTranscriptionFinished != true;

            if (event.outputTranscriptionFinished == true) {
              final msg = ChatMessage(
                content: _partialAiTranscript.trim(),
                role: 'assistant',
                agent: event.author,
              );
              _chatHistory.add(msg);
              _persistMessage(msg);
              _partialAiTranscript = '';
            }
          }

          // Input transcription (what the user said)
          if (event.inputTranscriptionText != null &&
              event.inputTranscriptionText!.isNotEmpty) {
             // Replace (not append) — API may send full accumulated text
             _partialUserTranscript = event.inputTranscriptionText!;
             _userTranscript = _partialUserTranscript;

            if (event.inputTranscriptionFinished == true) {
              final msg = ChatMessage(
                content: _partialUserTranscript.trim(),
                role: 'user',
              );
              _chatHistory.add(msg);
              _persistMessage(msg);
              _partialUserTranscript = '';
              _userTranscript = '';
            }
          }

          // Turn complete → AI stopped speaking, stop playback stream
          if (event.turnComplete == true) {
            _aiSpeaking = false;
            _stopPlaybackStream();
          }

          // Interrupted → AI was cut off, stop playback stream
          if (event.interrupted == true) {
            _aiSpeaking = false;
            _stopPlaybackStream();
          }
        });
      });

      // Listen for binary PCM audio from server.
      _startAudioPlaybackStream();

      // Start audio recording → binary PCM frames to WebSocket.
      _startAudioStreaming();

      // Start camera frame capture → JPEG to WebSocket.
      _startCameraStreaming();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _callStatus = 'Connection failed';
        });
      }
      debugPrint('Failed to connect: $e');
    }
  }

  /// Start listening for binary PCM audio frames from the server.
  void _startAudioPlaybackStream() {
    _audioByteSub = _wsService!.audioBytes.listen((pcmBytes) {
      if (!_playerOpen) return;
      // Start the player stream if not already playing.
      if (!_soundPlayer.isPlaying) {
        _soundPlayer.startPlayerFromStream(
          codec: Codec.pcm16,
          numChannels: 1,
          sampleRate: 24000,
        ).then((_) {
          debugPrint('[Audio] Player stream started');
          // Feed the first chunk after starting.
          _soundPlayer.foodSink?.add(FoodData(pcmBytes));
        }).catchError((e) {
          debugPrint('[Audio] startPlayerFromStream error: $e');
        });
      } else {
        // Stream already open — feed PCM data directly.
        _soundPlayer.foodSink?.add(FoodData(pcmBytes));
      }
      if (mounted && !_aiSpeaking) {
        setState(() => _aiSpeaking = true);
      }
    });
  }

  /// Stop the streaming playback.
  Future<void> _stopPlaybackStream() async {
    try {
      if (_soundPlayer.isPlaying) {
        await _soundPlayer.stopPlayer();
        debugPrint('[Audio] Player stream stopped');
      }
    } catch (e) {
      debugPrint('[Audio] stopPlayer error: $e');
    }
  }

  String get _formattedCallTime {
    final m = (_callSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _startAudioStreaming() {
    if (_isMuted) return;
    final audioStream = _audioService.startRecording();
    _audioSub = audioStream.listen((base64Chunk) {
      // Decode base64 → raw PCM bytes, then send as binary WS frame.
      // The `record` package returns base64-encoded PCM data.
      final bytes = base64Decode(base64Chunk);
      _wsService?.sendAudioBytes(Uint8List.fromList(bytes));
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

  /// Persist a message to local cache for history.
  void _persistMessage(ChatMessage msg) {
    _historyService.saveMessage(
      _sessionId,
      CachedMessage(
        id: msg.id,
        content: msg.content,
        role: msg.role,
        agent: msg.agent,
        timestamp: msg.timestamp.toIso8601String(),
      ),
    );
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
    _callTimer?.cancel();
    _stopAudioStreaming();
    _stopCameraStreaming();
    _audioService.dispose();
    _cameraService.dispose();
    _audioByteSub?.cancel();
    _stopPlaybackStream();
    if (_playerOpen) {
      _soundPlayer.closePlayer();
      _playerOpen = false;
    }
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

          // Top bar — status + timer.
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
                        if (_isConnected) ...[
                          const SizedBox(width: 12),
                          Text(_formattedCallTime,
                              style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                  fontFeatures: [const FontFeature.tabularFigures()])),
                        ],
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

          // Modality status chips — shows See/Hear/Speak states.
          if (_isConnected)
            Positioned(
              top: MediaQuery.of(context).padding.top + 50,
              left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ModalityChip(
                    icon: Icons.visibility_rounded,
                    label: 'Seeing',
                    active: _isCameraOn,
                  ),
                  const SizedBox(width: 8),
                  _ModalityChip(
                    icon: Icons.hearing_rounded,
                    label: 'Hearing',
                    active: !_isMuted,
                  ),
                  const SizedBox(width: 8),
                  _ModalityChip(
                    icon: Icons.record_voice_over_rounded,
                    label: 'Speaking',
                    active: _aiSpeaking,
                  ),
                ],
              ),
            ),

          // AI presence indicator + agent name.
          Positioned(
            top: size.height * 0.30,
            left: 0, right: 0,
            child: Center(
              child: Column(
                children: [
                  AnimatedBuilder(
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
                  const SizedBox(height: 12),
                  Text('Glow',
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    _aiSpeaking ? 'Speaking...' : 'Listening to you',
                    style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12),
                  ),
                ],
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
          // Full-screen connection overlay.
          if (_isConnecting)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 60, height: 60,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation(
                          const Color(0xFF6C63FF).withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Connecting to your\nAI advisor...',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.w500, height: 1.4)),
                    const SizedBox(height: 8),
                    Text('Setting up camera, microphone & voice',
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13)),
                    const SizedBox(height: 40),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel',
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),

          // Permission denied overlay.
          if (_permissionDenied)
            Container(
              color: Colors.black.withValues(alpha: 0.9),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mic_off_rounded, size: 64,
                          color: Colors.red.withValues(alpha: 0.7)),
                      const SizedBox(height: 20),
                      Text('Permissions Required',
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 20,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Text(
                        'Microphone access is needed for the live consultation. '
                        'Please enable it in your device settings.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 28),
                      ElevatedButton(
                        onPressed: () => openAppSettings(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text('Open Settings',
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Go Back',
                            style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.5))),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Connection failed overlay.
          if (!_isConnecting && !_isConnected && !_permissionDenied)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 56,
                        color: Colors.red.withValues(alpha: 0.7)),
                    const SizedBox(height: 20),
                    Text('Connection Failed',
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 20,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Could not connect to the AI advisor',
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14)),
                    const SizedBox(height: 28),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isConnecting = true;
                          _callStatus = 'Reconnecting...';
                        });
                        _initializeAll();
                      },
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                      label: Text('Retry',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Go Back',
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.5))),
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



/// Compact chip showing a modality state (See / Hear / Speak).
class _ModalityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _ModalityChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF6C63FF).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? const Color(0xFF6C63FF).withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4))),
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
