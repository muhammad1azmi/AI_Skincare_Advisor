import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/chat_history_service.dart';
import '../theme.dart';
import '../router.dart';
import 'consultation_screen.dart';
import 'chat_screen.dart';

/// Main app shell — consultation-first with drawer menu for other screens.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  /// Global key so child widgets can open the drawer.
  static final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.valueOrNull;
    final theme = Theme.of(context);

    return Scaffold(
      key: MainScreen.scaffoldKey,
      body: const ConsultationScreen(),
      endDrawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text('Menu',
                    style: GoogleFonts.inter(
                        fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline,
                    color: theme.colorScheme.primary),
                title: Text('Chat',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                subtitle: Text('Text conversation',
                    style: GoogleFonts.inter(fontSize: 12)),
                onTap: () {
                  Navigator.pop(context); // close drawer
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ChatScreen()));
                },
              ),
              ListTile(
                leading: Icon(Icons.history_rounded,
                    color: theme.colorScheme.primary),
                title: Text('History',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                subtitle: Text('Past consultations',
                    style: GoogleFonts.inter(fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const _HistoryTab()));
                },
              ),
              ListTile(
                leading: Icon(Icons.person_outline,
                    color: theme.colorScheme.primary),
                title: Text('Profile',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                subtitle: Text('Settings & account',
                    style: GoogleFonts.inter(fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => _ProfileTab(user: user)));
                },
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Glow • Your AI Skincare Advisor',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
// History Tab (extracted from home_screen.dart)
// ─────────────────────────────────────────────────────────────

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

    return Scaffold(
      appBar: AppBar(
        title: Text('History', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : sessions.isEmpty
                  ? Center(
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
                          Text(
                              'Start a consultation to begin\ntracking your skin progress',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7))),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSessions,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: sessions.length + 1,
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


// ─────────────────────────────────────────────────────────────
// Profile Tab (extracted from home_screen.dart)
// ─────────────────────────────────────────────────────────────

class _ProfileTab extends ConsumerWidget {
  final User? user;
  const _ProfileTab({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        centerTitle: false,
        actions: [
          // Notification bell
          IconButton(
            onPressed: () => _showNotificationSettings(context, ref),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: ListView(
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
      ),
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


// ─────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────

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
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
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
          Text('Notifications',
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
            SwitchListTile(
              title: Text('Routine Reminders',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              subtitle: const Text('Daily skincare routine notifications'),
              value: _routineReminders,
              onChanged: (v) {
                setState(() => _routineReminders = v);
                _savePrefs();
              },
            ),
            SwitchListTile(
              title: Text('Progress Updates',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              subtitle: const Text('Weekly skin progress reports'),
              value: _progressUpdates,
              onChanged: (v) {
                setState(() => _progressUpdates = v);
                _savePrefs();
              },
            ),
            SwitchListTile(
              title: Text('Product Deals',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              subtitle: const Text('Deals on recommended products'),
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
