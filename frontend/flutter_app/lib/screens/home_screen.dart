import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../router.dart';
import '../services/auth_service.dart';

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
                  onTap: () => Navigator.pushNamed(context, AppRoutes.chat),
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
                  onTap: () => Navigator.pushNamed(context, AppRoutes.chat),
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

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timeline_rounded, size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No history yet',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Start a consultation to begin\ntracking your skin progress',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
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
          onTap: () {},
        ),
        ListTile(
          leading: Icon(Icons.dark_mode_outlined, color: theme.colorScheme.primary),
          title: Text('Appearance', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          subtitle: const Text('Theme & display'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
        ListTile(
          leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
          title: Text('About', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          subtitle: const Text('Version 1.0.0'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
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
}
