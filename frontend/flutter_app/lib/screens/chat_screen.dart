import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../services/auth_service.dart';
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
  WebSocketService? _wsService;
  bool _isConnected = false;
  bool _isTyping = false;
  String _partialTranscript = '';
  late final String _sessionId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
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
      setState(() => _isConnected = true);

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
          _scrollToBottom();
        }

        // Handle output transcription (model's spoken words as text)
        if (event.outputTranscriptionText != null &&
            event.outputTranscriptionText!.isNotEmpty) {
          setState(() {
            _partialTranscript += event.outputTranscriptionText!;
            if (event.outputTranscriptionFinished == true) {
              // Finalize transcription as a message
              _isTyping = false;
              _messages.add(ChatMessage(
                content: _partialTranscript.trim(),
                role: 'assistant',
                agent: event.author,
              ));
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
        setState(() => _isConnected = false);
      });
    } catch (e) {
      debugPrint('WebSocket connection failed: $e');
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _wsService == null) return;

    setState(() {
      _messages.add(ChatMessage(content: text, role: 'user'));
      _isTyping = true;
    });
    _controller.clear();
    _wsService!.sendText(text);
    _scrollToBottom();
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
        title: const Text('Chat with Advisor'),
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
          Icon(Icons.chat_bubble_outline_rounded, size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Start a conversation',
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
                hintText: 'Type your question...',
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
