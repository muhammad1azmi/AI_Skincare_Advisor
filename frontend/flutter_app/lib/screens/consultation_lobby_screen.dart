import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../router.dart';

/// Pre-consultation lobby screen.
///
/// Shows camera preview, checks permissions, and gives the user
/// a clear "Start" button before connecting to the backend.
/// This prevents accidental backend calls and Vertex AI session costs.
class ConsultationLobbyScreen extends StatefulWidget {
  const ConsultationLobbyScreen({super.key});

  @override
  State<ConsultationLobbyScreen> createState() =>
      _ConsultationLobbyScreenState();
}

class _ConsultationLobbyScreenState extends State<ConsultationLobbyScreen> {
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _micGranted = false;
  bool _camGranted = false;
  bool _checkingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final micStatus = await Permission.microphone.status;
    final camStatus = await Permission.camera.status;

    setState(() {
      _micGranted = micStatus.isGranted;
      _camGranted = camStatus.isGranted;
      _checkingPermissions = false;
    });

    // If camera is already granted, initialize preview.
    if (_camGranted) {
      await _initCamera();
    }
  }

  Future<void> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    final camStatus = await Permission.camera.request();

    setState(() {
      _micGranted = micStatus.isGranted;
      _camGranted = camStatus.isGranted;
    });

    if (_camGranted && !_cameraReady) {
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('[Lobby] Camera init failed: $e');
    }
  }

  void _startConsultation() {
    // Dispose our preview camera before the consultation screen
    // creates its own camera instance.
    _cameraController?.dispose();
    _cameraController = null;
    Navigator.pushReplacementNamed(context, AppRoutes.consultation);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  bool get _canStart => _micGranted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Stack(
        children: [
          // Camera preview background (blurred + dimmed).
          if (_cameraReady && _cameraController != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.35,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize!.height,
                    height: _cameraController!.value.previewSize!.width,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),
            ),

          // Gradient overlay.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0D0D1A).withValues(alpha: 0.6),
                    const Color(0xFF0D0D1A).withValues(alpha: 0.95),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // Main content.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // Back button.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // AI avatar.
                  Container(
                    width: 100,
                    height: 100,
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
                        color: Colors.white, size: 48),
                  ).animate().fadeIn(duration: 500.ms).scale(
                      begin: const Offset(0.8, 0.8),
                      duration: 500.ms,
                      curve: Curves.easeOutBack),

                  const SizedBox(height: 28),

                  Text(
                    'Meet Glow',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                  const SizedBox(height: 12),

                  Text(
                    'Your AI skincare advisor will see your skin\n'
                    'via camera and talk to you in real-time.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                  ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

                  const SizedBox(height: 40),

                  // Permission status indicators.
                  if (!_checkingPermissions)
                    Column(
                      children: [
                        _PermissionRow(
                          icon: Icons.mic_rounded,
                          label: 'Microphone',
                          granted: _micGranted,
                          required: true,
                        ),
                        const SizedBox(height: 12),
                        _PermissionRow(
                          icon: Icons.videocam_rounded,
                          label: 'Camera',
                          granted: _camGranted,
                          required: false,
                        ),
                      ],
                    ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

                  if (!_micGranted && !_checkingPermissions) ...[
                    const SizedBox(height: 20),
                    TextButton.icon(
                      onPressed: _requestPermissions,
                      icon: const Icon(Icons.security_rounded, size: 18),
                      label: const Text('Grant Permissions'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6C63FF),
                      ),
                    ),
                  ],

                  const Spacer(flex: 3),

                  // Start button.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canStart ? _startConsultation : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        disabledBackgroundColor:
                            Colors.grey.withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 8,
                        shadowColor:
                            const Color(0xFF6C63FF).withValues(alpha: 0.4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_rounded, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Start Consultation',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 500.ms, duration: 400.ms)
                      .slideY(begin: 0.15),

                  const SizedBox(height: 12),

                  Text(
                    _canStart
                        ? 'Camera & microphone will activate after you start'
                        : 'Microphone permission is required to start',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool granted;
  final bool required;

  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.granted,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: granted
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon,
              color: granted
                  ? Colors.greenAccent
                  : Colors.white.withValues(alpha: 0.4),
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.8), fontSize: 15),
            ),
          ),
          if (!granted && required)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Required',
                  style: GoogleFonts.inter(
                      color: Colors.orange, fontSize: 11,
                      fontWeight: FontWeight.w500)),
            )
          else if (!granted)
            Text('Optional',
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12))
          else
            Icon(Icons.check_circle_rounded,
                color: Colors.greenAccent.withValues(alpha: 0.7), size: 20),
        ],
      ),
    );
  }
}
