import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../services/auth_service.dart';
import '../services/chat_history_service.dart';
import '../services/websocket_service.dart';

/// Chat message model.
class ChatMessage {
  final String id;
  final String content;
  final String role;
  final String? agent;
  final DateTime timestamp;

  ChatMessage({
    String? id,
    required this.content,
    required this.role,
    this.agent,
    DateTime? timestamp,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();
}

/// Text chat screen with message bubbles and ADK WebSocket streaming.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final _historyService = ChatHistoryService();
  WebSocketService? _wsService;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isTyping = false;
  String _partialTranscript = '';
  String? _sessionId;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    // Defer route argument reading to after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _sessionId = args['sessionId'] as String?;
        final initialMessages = args['initialMessages'] as List<ChatMessage>?;
        if (initialMessages != null && initialMessages.isNotEmpty) {
          setState(() => _messages.addAll(initialMessages));
          _scrollToBottom();
        }
        // Pre-fill message from Quick Actions.
        final prefill = args['prefill'] as String?;
        if (prefill != null && prefill.isNotEmpty) {
          _controller.text = prefill;
          // Auto-send after a short delay for UX polish.
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) _sendMessage();
          });
        }
      }
      _sessionId ??= const Uuid().v4();
      // Load cached messages for this session.
      if (_messages.isEmpty) {
        _loadCachedMessages();
      }
    });
  }

  Future<void> _ensureConnected() async {
    if (_isConnected || _isConnecting) return;
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    final authService = ref.read(authServiceProvider);
    final user = authService.currentUser;
    final userId = user?.uid ?? 'guest_${const Uuid().v4().substring(0, 8)}';
    final token = await authService.getIdToken();

    _wsService = WebSocketService(
      userId: userId,
      sessionId: _sessionId!,
      authToken: token,
    );

    try {
      await _wsService!.connect();
      if (!mounted) return;
      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });

      // Listen for ADK events from the server.
      _wsService!.events.listen((event) {
        // Handle text content from the agent
        if (event.textContent != null && event.textContent!.isNotEmpty) {
          setState(() {
            _isTyping = false;
            _messages.add(ChatMessage(
              content: event.textContent!,
              role: 'assistant',
              agent: event.author,
            ));
          });
          _cacheMessage(event.textContent!, 'assistant', agent: event.author);
          _scrollToBottom();
        }

        // Handle output transcription (model's spoken words as text)
        if (event.outputTranscriptionText != null &&
            event.outputTranscriptionText!.isNotEmpty) {
          setState(() {
            _partialTranscript += event.outputTranscriptionText!;
            if (event.outputTranscriptionFinished == true) {
              _isTyping = false;
              final transcript = _partialTranscript.trim();
              _messages.add(ChatMessage(
                content: transcript,
                role: 'assistant',
                agent: event.author,
              ));
              _cacheMessage(transcript, 'assistant', agent: event.author);
              _partialTranscript = '';
            }
          });
          _scrollToBottom();
        }

        // Handle turn complete
        if (event.turnComplete == true) {
          setState(() => _isTyping = false);
        }
      }, onError: (e) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
        });
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionError = 'Could not connect. Tap send to retry.';
        });
      }
      debugPrint('WebSocket connection failed: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Add user message immediately for responsive feel.
    setState(() {
      _messages.add(ChatMessage(content: text, role: 'user'));
      _isTyping = true;
      _connectionError = null;
    });
    _controller.clear();
    _scrollToBottom();
    _cacheMessage(text, 'user');

    // Lazy connect on first message.
    if (!_isConnected) {
      await _ensureConnected();
      if (!_isConnected) {
        // Connection failed — revert typing state.
        setState(() => _isTyping = false);
        return;
      }
    }

    _wsService!.sendText(text);
  }

  Future<void> _loadCachedMessages() async {
    if (_sessionId == null) return;
    final cached = await _historyService.loadMessages(_sessionId!);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages.addAll(cached.map((c) => ChatMessage(
              id: c.id,
              content: c.content,
              role: c.role,
              agent: c.agent,
              timestamp: DateTime.tryParse(c.timestamp) ?? DateTime.now(),
            )));
      });
      _scrollToBottom();
    }
  }

  void _cacheMessage(String content, String role, {String? agent}) {
    if (_sessionId == null) return;
    _historyService.saveMessage(
      _sessionId!,
      CachedMessage(
        id: const Uuid().v4(),
        content: content,
        role: role,
        agent: agent,
        timestamp: DateTime.now().toIso8601String(),
      ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _wsService?.sendEnd();
    _wsService?.disconnect();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00BFA5)],
                ),
              ),
              child: const Icon(Icons.face_retouching_natural,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Glow', style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.w600)),
                Text('AI Skincare Advisor',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.circle, size: 10,
                color: _isConnected ? Colors.green : Colors.red),
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner.
          if (_isConnecting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Connecting to advisor...',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: theme.colorScheme.primary)),
                ],
              ),
            ),
          if (_connectionError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: theme.colorScheme.error.withValues(alpha: 0.1),
              child: Text(_connectionError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.error)),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) return _buildTypingIndicator(theme);
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.face_retouching_natural, size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Chat with Glow',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('Ask about skincare routines,\ningredients, or skin concerns',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SizedBox(
          width: 48, height: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (i) => _AnimatedDot(delay: i * 200)),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (text) => _sendMessage(),
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Ask Glow anything...',
                hintStyle: GoogleFonts.inter(fontSize: 15),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _sendMessage,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && message.agent != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.agent!.replaceAll('_', ' ').toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary, letterSpacing: 0.5,
                  ),
                ),
              ),
            Text(
              message.content,
              style: GoogleFonts.inter(
                fontSize: 15, height: 1.4,
                color: isUser ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDot extends StatefulWidget {
  final int delay;
  const _AnimatedDot({this.delay = 0});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary
              .withValues(alpha: 0.3 + _ctrl.value * 0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
