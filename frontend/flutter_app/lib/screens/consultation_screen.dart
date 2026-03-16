import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'chat_screen.dart';
import 'main_screen.dart';
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
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _hasStarted = false; // User tapped 'Start'
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _aiSpeaking = false;
  bool _toolCallActive = false; // Gate audio/video during tool execution
  String? _lastToolCallName;     // Deduplicate tool call events
  DateTime? _lastToolCallTime;
  bool _permissionDenied = false;
  bool _showTranscript = false;
  bool _initialized = false;
  String _transcript = '';
  String _userTranscript = '';
  String _callStatus = 'Tap Start to begin';
  String _sessionId = const Uuid().v4();

  // Call timer
  Timer? _callTimer;
  int _callSeconds = 0;

  // Transcript history — collects user/AI messages for the chat screen.
  final List<ChatMessage> _chatHistory = [];
  String _partialAiTranscript = '';
  String _partialUserTranscript = '';

  // Audio playback subscription for binary PCM frames
  StreamSubscription<Uint8List>? _audioByteSub;
  final List<Uint8List> _audioPlaybackQueue = [];
  final List<int> _pcmAccumulator = []; // Buffer PCM bytes for WAV playback
  Timer? _playbackTimer; // Periodic timer to flush accumulated PCM as WAV
  bool _isPlayingChunk = false; // Guard against overlapping playback calls
  bool _playbackCooldown = false; // Post-playback cooldown to prevent VAD barge-in
  Timer? _cooldownTimer;

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
    // Don't auto-connect — wait for user to tap Start
  }

  Future<void> _initializeAll() async {
    // Prevent duplicate initialization
    if (_initialized) return;
    _initialized = true;

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
      // Keep _isConnecting = true until "Session ready" arrives.
      // This prevents the "Connection failed" overlay from flashing.
      setState(() {
        _callStatus = 'Connecting to Glow...';
      });

      // Listen for ADK events.
      _wsService!.events.listen((event) {
        setState(() {
          // Handle server status messages (e.g. "Session ready")
          if (event.statusMessage != null) {
            _callStatus = event.statusMessage!;
            if (event.statusMessage!.contains('Session ready') && !_isConnected) {
              _isConnected = true;
              _isConnecting = false; // NOW it's safe to clear the connecting state
              _callStatus = 'Connected';
              // Start call timer only once Gemini is responding
              _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
                if (mounted) setState(() => _callSeconds++);
              });
              HapticFeedback.mediumImpact();
            }
            return;
          }

          // Text content from agent (non-streaming text response)
          // In voice mode, the spoken version arrives via outputTranscriptionText.
          // Only add textContent if it's a unique message not already in history.
          if (event.textContent != null && event.textContent!.isNotEmpty) {
            _transcript = event.textContent!;
            // Skip adding to chat if outputTranscription will handle it
            // (voice mode sends the same content via both channels).
            // Only add if it looks like a tool result or unique content.
          }

          // Sub-agent tool events (call started / result received)
          if (event.toolEvent == 'call' && event.toolName != null) {
            // Deduplicate: Gemini Live sometimes fires the same
            // function_call event twice in the downstream stream.
            // Skip if same tool was called within 3 seconds.
            final now = DateTime.now();
            if (_lastToolCallName == event.toolName &&
                _lastToolCallTime != null &&
                now.difference(_lastToolCallTime!).inSeconds < 3) {
              debugPrint('[Tool] Skipping duplicate call to ${event.toolName}');
            } else {
              _lastToolCallName = event.toolName;
              _lastToolCallTime = now;
              // Gate realtime input: Gemini Live API rejects sendRealtimeInput
              // while processing a tool call, causing 1008 policy violations
              // or keepalive timeouts. Stop sending audio/video until result.
              _toolCallActive = true;
              // Show a status message so user knows Glow is working
              final prettyName = event.toolName!.replaceAll('_', ' ');
              final msg = ChatMessage(
                content: '🔍 Analyzing with $prettyName...',
                role: 'assistant',
                agent: event.toolName,
              );
              _chatHistory.add(msg);
            }
          }
          if (event.toolEvent == 'result' &&
              event.toolResult != null &&
              event.toolResult!.isNotEmpty) {
            // Don't show raw sub-agent results as chat messages.
            // The root agent summarizes the key findings via voice,
            // and the raw text often contains internal instructions
            // (e.g. 'Root orchestrator, please describe...') that
            // should never be shown to the user.
            debugPrint('[Tool] Result received from ${event.toolName} '
                '(${event.toolResult!.length} chars) — not displaying');
            _toolCallActive = false; // Ungate realtime input
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
              final trimmed = _partialAiTranscript.trim();
              // Deduplicate: skip if last message has same content
              if (trimmed.isNotEmpty && (_chatHistory.isEmpty ||
                  _chatHistory.last.content != trimmed)) {
                final msg = ChatMessage(
                  content: trimmed,
                  role: 'assistant',
                  agent: event.author,
                );
                _chatHistory.add(msg);
                _persistMessage(msg);
              }
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
              final trimmed = _partialUserTranscript.trim();
              // Skip very short transcriptions (≤2 chars) — these are
              // typically noise artifacts from VAD, not real user speech.
              if (trimmed.length > 2) {
                final msg = ChatMessage(
                  content: trimmed,
                  role: 'user',
                );
                _chatHistory.add(msg);
                _persistMessage(msg);
              } else {
                debugPrint('[Transcript] Skipping noise transcript: "$trimmed"');
              }
              _partialUserTranscript = '';
              _userTranscript = '';
            }
          }

          // Turn complete → Gemini finished generating audio for this turn.
          // DON'T stop playback! Audio chunks may still be queued/playing.
          // Just mark flags; playback drains naturally via _playNextInQueue.
          if (event.turnComplete == true) {
            _aiSpeaking = false;
            _toolCallActive = false; // Safety: always clear on turn complete
            // Note: _isPlayingChunk, _audioPlaybackQueue, and _playbackCooldown
            // will be handled by the playback chain finishing on its own.
          }

          // Interrupted → server-side VAD thinks user spoke during AI audio.
          // IGNORE: don't clear queue or stop playback. Let the AI finish
          // its full response. Our client-side gating already prevents
          // mic audio during playback, so these are false positives from
          // background noise or speaker echo.
          if (event.interrupted == true) {
            debugPrint('[Audio] Ignoring interrupted event — letting AI finish');
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
    // Accumulate PCM chunks as they arrive.
    _audioByteSub = _wsService!.audioBytes.listen((pcmBytes) {
      _pcmAccumulator.addAll(pcmBytes);

      if (mounted && !_aiSpeaking) {
        setState(() => _aiSpeaking = true);
      }

      // Once we have enough audio (~500ms), queue it and start playback.
      // Larger chunks = fewer temp files, less I/O, smoother audio.
      if (_pcmAccumulator.length >= 24000) {
        final pcmData = Uint8List.fromList(_pcmAccumulator);
        _pcmAccumulator.clear();
        final wavData = _buildWav(pcmData, sampleRate: 24000, channels: 1, bitsPerSample: 16);
        _audioPlaybackQueue.add(wavData);
        // Start playing if not already playing.
        if (!_isPlayingChunk) {
          _playNextInQueue();
        }
      }
    });
  }

  /// Play the next WAV buffer from the queue, sequentially.
  Future<void> _playNextInQueue() async {
    if (_audioPlaybackQueue.isEmpty || !_playerOpen) {
      _isPlayingChunk = false;
      // Start a cooldown: the speaker may still be physically emitting
      // the tail end of audio. Wait 800ms before allowing mic audio
      // to be sent again, so VAD doesn't pick up echo.
      _cooldownTimer?.cancel();
      _playbackCooldown = true;
      _cooldownTimer = Timer(const Duration(milliseconds: 800), () {
        _playbackCooldown = false;
      });
      return;
    }

    _isPlayingChunk = true;
    final wavData = _audioPlaybackQueue.removeAt(0);

    try {
      final tempDir = await Directory.systemTemp.createTemp('audio_');
      final tempFile = File('${tempDir.path}/chunk.wav');
      await tempFile.writeAsBytes(wavData);

      await _soundPlayer.startPlayer(
        fromURI: tempFile.path,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          tempFile.delete().catchError((_) => tempFile);
          tempDir.delete().catchError((_) => tempDir);
          // Play next in queue, or mark as done.
          _playNextInQueue();
        },
      );
    } catch (e) {
      debugPrint('[Audio] Playback error: $e');
      _isPlayingChunk = false;
      // Try next chunk even if this one failed.
      if (_audioPlaybackQueue.isNotEmpty) {
        _playNextInQueue();
      }
    }
  }

  /// Build a WAV file from raw PCM data.
  Uint8List _buildWav(Uint8List pcmData, {required int sampleRate, required int channels, required int bitsPerSample}) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57);  // W
    buffer.setUint8(9, 0x41);  // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E
    // fmt sub-chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // (space)
    buffer.setUint32(16, 16, Endian.little); // Sub-chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, channels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitsPerSample, Endian.little);
    // data sub-chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);
    // PCM data
    final bytes = buffer.buffer.asUint8List();
    bytes.setRange(44, 44 + dataSize, pcmData);
    return bytes;
  }

  /// Stop the streaming playback.
  Future<void> _stopPlaybackStream() async {
    // Clear the queue and accumulator.
    _audioPlaybackQueue.clear();
    _pcmAccumulator.clear();
    _isPlayingChunk = false;
    _cooldownTimer?.cancel();
    _playbackCooldown = false;
    try {
      if (_soundPlayer.isPlaying) await _soundPlayer.stopPlayer();
    } catch (_) {}
    debugPrint('[Audio] Turn ended');
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
      // Full audio gate — suppress mic in all these scenarios:
      // 1. AI is speaking (transcription still arriving)
      // 2. Audio chunk is currently playing through speaker
      // 3. More chunks are queued to play
      // 4. Cooldown period after last chunk finished (speaker echo)
      // 5. Tool call is active (prevents Gemini 1008)
      if (_aiSpeaking ||
          _isPlayingChunk ||
          _audioPlaybackQueue.isNotEmpty ||
          _playbackCooldown ||
          _toolCallActive) return;

      // Decode base64 → raw PCM bytes, then send as binary WS frame.
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
      // Gate camera frames during AI speech and tool calls.
      // Sending visual input during speech can trigger Gemini VAD barge-in.
      if (_toolCallActive ||
          _aiSpeaking ||
          _isPlayingChunk ||
          _audioPlaybackQueue.isNotEmpty ||
          _playbackCooldown) return;
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
    _callTimer?.cancel();
    _wsService?.sendEnd();
    _wsService?.disconnect();

    // Reset to idle start state (no auto-reconnect)
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _hasStarted = false;
        _callSeconds = 0;
        _callStatus = 'Tap Start to begin';
        _transcript = '';
        _userTranscript = '';
        _aiSpeaking = false;
        _showTranscript = false;
        _initialized = false;
        _sessionId = const Uuid().v4(); // New session on next start
      });
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
    _playbackTimer?.cancel();
    _pcmAccumulator.clear();
    try {
      if (_soundPlayer.isPlaying) _soundPlayer.stopPlayer();
    } catch (_) {}
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

    return Container(
      color: Colors.black,
      child: Stack(
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
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () {
                      MainScreen.scaffoldKey.currentState?.openEndDrawer();
                    },
                    icon: const Icon(Icons.menu_rounded,
                        color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Single turn indicator — replaces Seeing/Hearing/Speaking chips
          if (_isConnected)
            Positioned(
              top: MediaQuery.of(context).padding.top + 50,
              left: 0, right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    // Determine current state
                    final isSpeaking = _aiSpeaking || _isPlayingChunk || _audioPlaybackQueue.isNotEmpty;
                    final isAnalyzing = _toolCallActive;

                    final Color bgColor;
                    final String label;
                    final IconData icon;

                    if (isAnalyzing) {
                      bgColor = const Color(0xFFFF9800).withValues(alpha: 0.85);
                      label = '🔍  Analyzing...';
                      icon = Icons.hourglass_top_rounded;
                    } else if (isSpeaking) {
                      final glowOpacity = 0.3 + (_pulseController.value * 0.3);
                      bgColor = const Color(0xFF6C63FF).withValues(alpha: 0.85);
                      label = '✨  Glow is speaking';
                      icon = Icons.graphic_eq_rounded;
                    } else {
                      bgColor = Colors.white.withValues(alpha: 0.15);
                      label = '🎤  Your turn';
                      icon = Icons.mic_rounded;
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: isSpeaking ? [
                          BoxShadow(
                            color: const Color(0xFF6C63FF).withValues(
                                alpha: 0.3 + (_pulseController.value * 0.3)),
                            blurRadius: 20, spreadRadius: 2,
                          ),
                        ] : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(label,
                            style: GoogleFonts.inter(
                                color: Colors.white, fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

          // Live transcript (AI response) — hidden when panel is open.
          if (_transcript.isNotEmpty && !_showTranscript)
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

          // User speech transcript (real-time) — hidden when panel is open.
          if (_userTranscript.isNotEmpty && !_showTranscript)
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
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    color: _showTranscript
                        ? const Color(0xFF6C63FF)
                        : Colors.white.withValues(alpha: 0.2),
                    onTap: () => setState(() => _showTranscript = !_showTranscript),
                  ),
                  _CallBtn(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: Colors.red,
                    large: true,
                    onTap: _endCall,
                  ),
                  _CallBtn(
                    icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                    label: _isCameraOn ? 'Camera' : 'Off',
                    color: !_isCameraOn ? Colors.red : Colors.white.withValues(alpha: 0.2),
                    onTap: _toggleCamera,
                  ),
                ],
              ),
            ),
          ),

          // Transcript peek panel.
          if (_showTranscript)
            Positioned(
              bottom: 140, left: 0, right: 0, top: MediaQuery.of(context).padding.top + 60,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Icon(Icons.subtitles_rounded,
                              color: Colors.white.withValues(alpha: 0.7), size: 18),
                          const SizedBox(width: 8),
                          Text('Live Transcript',
                              style: GoogleFonts.inter(
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          IconButton(
                            onPressed: () => setState(() => _showTranscript = false),
                            icon: Icon(Icons.close_rounded,
                                color: Colors.white.withValues(alpha: 0.5), size: 20),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                    // Messages
                    Expanded(
                      child: _chatHistory.isEmpty
                          ? Center(
                              child: Text('Transcript will appear here...',
                                  style: GoogleFonts.inter(
                                      color: Colors.white.withValues(alpha: 0.3),
                                      fontSize: 13)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              reverse: true,
                              itemCount: _chatHistory.length,
                              itemBuilder: (ctx, i) {
                                final msg = _chatHistory[_chatHistory.length - 1 - i];
                                final isUser = msg.role == 'user';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24, height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isUser
                                              ? Colors.white.withValues(alpha: 0.15)
                                              : const Color(0xFF6C63FF).withValues(alpha: 0.3),
                                        ),
                                        child: Icon(
                                          isUser ? Icons.person : Icons.auto_awesome,
                                          color: Colors.white.withValues(alpha: 0.7),
                                          size: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isUser ? 'You' : 'Glow',
                                              style: GoogleFonts.inter(
                                                  color: Colors.white.withValues(alpha: 0.5),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              msg.content,
                                              style: GoogleFonts.inter(
                                                  color: Colors.white.withValues(alpha: 0.85),
                                                  fontSize: 13, height: 1.4),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          // Full-screen idle overlay (before user starts).
          if (!_hasStarted)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1a1a2e), Color(0xFF0f3460)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated glow icon
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseController.value * 0.08);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 100, height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF6C63FF), Color(0xFF00BFA5)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.auto_awesome,
                                  color: Colors.white, size: 44),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text('Glow',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Your AI Skincare Advisor',
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14)),
                      const SizedBox(height: 48),
                      // Start button
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _hasStarted = true;
                            _isConnecting = true;
                            _callStatus = 'Connecting...';
                          });
                          _initializeAll();
                        },
                        child: Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00BFA5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00BFA5).withValues(alpha: 0.4),
                                blurRadius: 20, spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.videocam_rounded,
                              color: Colors.white, size: 36),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Start Consultation',
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
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
                      onPressed: () {
                        setState(() {
                          _isConnecting = false;
                          _callStatus = 'Disconnected';
                        });
                      },
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
                        onPressed: () => openAppSettings(),
                        child: Text('Try Again',
                            style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.5))),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Connection failed overlay.
          if (_hasStarted && !_isConnecting && !_isConnected && !_permissionDenied)
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
                      onPressed: () {
                        setState(() => _callStatus = 'Disconnected');
                      },
                      child: Text('Dismiss',
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
