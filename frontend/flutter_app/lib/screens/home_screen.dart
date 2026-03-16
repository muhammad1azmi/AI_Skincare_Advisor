import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router.dart';
import '../services/auth_service.dart';
import '../services/chat_history_service.dart';
import '../theme.dart';

/// Home dashboard with quick-action cards.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);
    final user = authState.valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: _currentIndex == 0
            ? _buildDashboard(context, theme, user)
            : _currentIndex == 1
                ? const _HistoryTab()
                : _ProfileTab(user: user),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, ThemeData theme, User? user) {
    final displayName = user?.displayName ?? 'there';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $displayName! 👋',
            style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2),
          const SizedBox(height: 4),
          Text(
            'How can I help your skin today?',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ).animate().fadeIn(delay: 100.ms, duration: 400.ms),
          const SizedBox(height: 32),

          // Main CTAs
          _ActionCard(
            icon: Icons.videocam_rounded,
            title: 'Live Consultation',
            subtitle: 'Video-call with AI advisor\nusing camera & voice',
            gradient: const [Color(0xFF6C63FF), Color(0xFF9B8FFF)],
            onTap: () => Navigator.pushNamed(context, AppRoutes.consultation),
          ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.1),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.chat_bubble_rounded,
            title: 'Chat with Advisor',
            subtitle: 'Text-based skincare advice\nand product questions',
            gradient: const [Color(0xFF00BFA5), Color(0xFF4DD0B8)],
            onTap: () => Navigator.pushNamed(context, AppRoutes.chat),
          ).animate().fadeIn(delay: 350.ms, duration: 500.ms).slideY(begin: 0.1),
          const SizedBox(height: 32),

          Text(
            'Quick Actions',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600),
          ).animate().fadeIn(delay: 450.ms),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.camera_alt_outlined,
                  label: 'Scan\nProduct',
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.chat,
                    arguments: {
                      'prefill': 'I want to scan a skincare product. '
                          'Please help me analyze its ingredients.',
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickAction(
                  icon: Icons.trending_up_rounded,
                  label: 'View\nProgress',
                  onTap: () => setState(() => _currentIndex = 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickAction(
                  icon: Icons.lightbulb_outline,
                  label: 'Skincare\nTips',
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.chat,
                    arguments: {
                      'prefill': 'Give me some personalized skincare tips '
                          'for my daily routine.',
                    },
                  ),
                ),
              ),
            ],
          ).animate().fadeIn(delay: 550.ms, duration: 500.ms),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 28),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  final _historyService = ChatHistoryService();
  List<SessionInfo> _remoteSessions = [];
  List<String> _localSessionIds = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(authServiceProvider);
      final user = authService.currentUser;
      final token = await authService.getIdToken();

      // Load from both sources in parallel.
      final results = await Future.wait([
        _historyService.fetchSessions(
          userId: user?.uid ?? 'guest',
          authToken: token,
        ),
        _historyService.getLocalSessionIds(),
      ]);

      if (mounted) {
        setState(() {
          _remoteSessions = results[0] as List<SessionInfo>;
          _localSessionIds = results[1] as List<String>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load sessions';
          _isLoading = false;
        });
      }
    }
  }

  /// Merge remote sessions with local-only sessions.
  List<_SessionDisplay> get _mergedSessions {
    final remoteIds = _remoteSessions.map((s) => s.sessionId).toSet();
    final merged = <_SessionDisplay>[];

    for (final s in _remoteSessions) {
      merged.add(_SessionDisplay(
        sessionId: s.sessionId,
        lastMessage: s.lastMessage,
        date: s.lastUpdateTime ?? s.createTime,
        messageCount: s.messageCount,
      ));
    }

    // Add local-only sessions not in remote list.
    for (final id in _localSessionIds) {
      if (!remoteIds.contains(id)) {
        merged.add(_SessionDisplay(
          sessionId: id,
          lastMessage: 'Locally cached session',
          date: null,
          messageCount: 0,
        ));
      }
    }

    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = _mergedSessions;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48,
                color: theme.colorScheme.error.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(_error!, style: GoogleFonts.inter(
                color: theme.colorScheme.error, fontSize: 14)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _loadSessions,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timeline_rounded, size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No history yet',
                style: GoogleFonts.inter(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Start a consultation to begin\ntracking your skin progress',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sessions.length + 1, // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Text('${sessions.length} session(s)',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6))),
            );
          }
          final s = sessions[index - 1];
          return _SessionCard(
            session: s,
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.chat,
                  arguments: {'sessionId': s.sessionId});
            },
          );
        },
      ),
    );
  }
}

class _SessionDisplay {
  final String sessionId;
  final String lastMessage;
  final String? date;
  final int messageCount;

  _SessionDisplay({
    required this.sessionId,
    required this.lastMessage,
    this.date,
    required this.messageCount,
  });

  String get displayDate {
    if (date == null) return '';
    try {
      final dt = DateTime.parse(date!);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}

class _SessionCard extends StatelessWidget {
  final _SessionDisplay session;
  final VoidCallback onTap;

  const _SessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                ),
                child: Icon(Icons.chat_bubble_outline_rounded,
                    color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Consultation',
                              style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (session.displayDate.isNotEmpty)
                          Text(session.displayDate,
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.5))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.3),
                  size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends ConsumerWidget {
  final User? user;
  const _ProfileTab({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 20),
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: user?.photoURL != null
                ? NetworkImage(user!.photoURL!)
                : null,
            child: user?.photoURL == null
                ? Icon(Icons.person, size: 48, color: theme.colorScheme.primary)
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            user?.displayName ?? 'Guest User',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        if (user?.email != null)
          Center(
            child: Text(user!.email!,
                style: GoogleFonts.inter(fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
        const SizedBox(height: 32),
        const Divider(),
        ListTile(
          leading: Icon(Icons.notifications_outlined, color: theme.colorScheme.primary),
          title: Text('Notifications', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          subtitle: const Text('Routine reminders & tips'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showNotificationSettings(context, ref),
        ),
        ListTile(
          leading: Icon(Icons.dark_mode_outlined, color: theme.colorScheme.primary),
          title: Text('Appearance', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          subtitle: const Text('Theme & display'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAppearanceSheet(context, ref),
        ),
        ListTile(
          leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
          title: Text('About', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          subtitle: const Text('Version 1.0.0'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Glow',
            applicationVersion: '1.0.0',
            applicationIcon: Container(
              width: 48, height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00BFA5)],
                ),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: Colors.white, size: 28),
            ),
            children: [
              const SizedBox(height: 8),
              Text(
                'Glow is your personal AI-powered skincare advisor. '
                'Get real-time skin analysis, personalized routines, '
                'and product recommendations — all powered by Google Gemini.',
                style: GoogleFonts.inter(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Built with Flutter, Firebase & ADK',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (user != null)
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, AppRoutes.login);
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
      ],
    );
  }

  void _showNotificationSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _NotificationSettingsSheet(),
    );
  }

  void _showAppearanceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer(builder: (context, ref, _) {
          final current = ref.watch(themeModeProvider);
          final notifier = ref.read(themeModeProvider.notifier);
          final theme = Theme.of(context);

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Appearance',
                    style: GoogleFonts.inter(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Choose your preferred theme',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                _ThemeOption(
                  icon: Icons.brightness_auto_rounded,
                  label: 'System Default',
                  subtitle: 'Follows your device settings',
                  selected: current == ThemeMode.system,
                  onTap: () => notifier.setMode(ThemeMode.system),
                ),
                const SizedBox(height: 8),
                _ThemeOption(
                  icon: Icons.light_mode_rounded,
                  label: 'Light',
                  subtitle: 'Always use light theme',
                  selected: current == ThemeMode.light,
                  onTap: () => notifier.setMode(ThemeMode.light),
                ),
                const SizedBox(height: 8),
                _ThemeOption(
                  icon: Icons.dark_mode_rounded,
                  label: 'Dark',
                  subtitle: 'Always use dark theme',
                  selected: current == ThemeMode.dark,
                  onTap: () => notifier.setMode(ThemeMode.dark),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

/// Bottom sheet with notification preference toggles.
class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet();

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<_NotificationSettingsSheet> {
  bool _routineReminders = true;
  bool _progressUpdates = true;
  bool _productDeals = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _routineReminders = prefs.getBool('notif_routine') ?? true;
      _progressUpdates = prefs.getBool('notif_progress') ?? true;
      _productDeals = prefs.getBool('notif_deals') ?? true;
      _loaded = true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_routine', _routineReminders);
    await prefs.setBool('notif_progress', _progressUpdates);
    await prefs.setBool('notif_deals', _productDeals);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Notification Preferences',
              style: GoogleFonts.inter(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Choose which notifications you receive',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          if (!_loaded)
            const Center(child: CircularProgressIndicator())
          else ...[
            _NotifToggle(
              icon: Icons.alarm_rounded,
              title: 'Routine Reminders',
              subtitle: 'Morning & evening skincare reminders',
              value: _routineReminders,
              onChanged: (v) {
                setState(() => _routineReminders = v);
                _savePrefs();
              },
            ),
            const SizedBox(height: 12),
            _NotifToggle(
              icon: Icons.trending_up_rounded,
              title: 'Progress Updates',
              subtitle: 'Milestone celebrations & check-in nudges',
              value: _progressUpdates,
              onChanged: (v) {
                setState(() => _progressUpdates = v);
                _savePrefs();
              },
            ),
            const SizedBox(height: 12),
            _NotifToggle(
              icon: Icons.local_offer_rounded,
              title: 'Product Deals',
              subtitle: 'Discounts on recommended products',
              value: _productDeals,
              onChanged: (v) {
                setState(() => _productDeals = v);
                _savePrefs();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _NotifToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7))),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.inter(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7))),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: theme.colorScheme.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
