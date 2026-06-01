import 'package:flutter/material.dart';

import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/notification_state.dart';
import '../../widgets/avatar_upload.dart';
import '../../widgets/modern_banner.dart';
import '../host/become_host_screen.dart';
import '../host/host_dashboard_screen.dart';
import '../notifications/notification_settings_screen.dart';
import '../verification/nid_verification_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.authState,
    required this.repository,
    this.notificationState,
  });

  final AuthStateNotifier authState;
  final MusafirRepository repository;
  final NotificationStateNotifier? notificationState;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AuthStateNotifier get authState => widget.authState;
  MusafirRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: false,
      ),
      body: ListenableBuilder(
        listenable: authState,
        builder: (context, _) {
          final user = authState.currentUser;

          if (user == null) {
            return _buildLoginPrompt(context, theme);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // User info card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        AvatarUpload(
                          currentAvatarUrl: user.avatarUrl,
                          userName: user.name,
                          userId: user.id,
                          radius: 40,
                          onAvatarChanged: (newUrl) {
                            // Update the user's avatar URL
                            authState.updateAvatar(newUrl);
                          },
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      user.name,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (user.isHost)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            theme.colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.home,
                                            size: 14,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Host',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (user.email != null)
                                Text(
                                  user.email!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (user.phone != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  user.phone!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Settings section
                _SettingsSection(
                  title: 'Settings',
                  items: [
                    _SettingsItem(
                      icon: Icons.person_outline,
                      title: 'Personal information',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsItem(
                      icon: Icons.verified_user_outlined,
                      title: 'Identity verification',
                      subtitle: 'Verify your identity with NID',
                      onTap: () => _navigateToVerification(context, user.id),
                    ),
                    _SettingsItem(
                      icon: Icons.security_outlined,
                      title: 'Login & security',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsItem(
                      icon: Icons.payment_outlined,
                      title: 'Payments & payouts',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsItem(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      onTap: () => _navigateToNotificationSettings(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Hosting section
                _SettingsSection(
                  title: 'Hosting',
                  items: [
                    if (!user.isHost)
                      _SettingsItem(
                        icon: Icons.home_work_outlined,
                        title: 'Become a Host',
                        subtitle: 'Start earning by sharing your space',
                        onTap: () => _navigateToBecomeHost(context),
                      )
                    else ...[
                      _SettingsItem(
                        icon: Icons.dashboard_outlined,
                        title: 'Host Dashboard',
                        subtitle: 'Manage your listings and bookings',
                        onTap: () => _navigateToHostDashboard(context),
                      ),
                      _SettingsItem(
                        icon: Icons.add_home_outlined,
                        title: 'Create New Listing',
                        onTap: () => _navigateToHostDashboard(context),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),

                // Support section
                _SettingsSection(
                  title: 'Support',
                  items: [
                    _SettingsItem(
                      icon: Icons.help_outline,
                      title: 'Get help',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsItem(
                      icon: Icons.article_outlined,
                      title: 'Terms of service',
                      onTap: () => _showComingSoon(context),
                    ),
                    _SettingsItem(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy policy',
                      onTap: () => _showComingSoon(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Logout button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmLogout(context),
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Version info
                Text(
                  'Musafir v1.0.0',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'Log in to view your profile',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Once you log in, your profile information will appear here.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ModernBanner.showInfo(context, 'Coming soon!');
  }

  void _navigateToNotificationSettings(BuildContext context) {
    if (widget.notificationState == null) {
      _showComingSoon(context);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationSettingsScreen(
          notificationState: widget.notificationState!,
        ),
      ),
    );
  }

  void _navigateToVerification(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NidVerificationScreen(
          userId: userId,
          onVerificationSubmitted: () {
            // Optionally refresh user data
          },
        ),
      ),
    );
  }

  void _navigateToBecomeHost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BecomeHostScreen(
          authState: authState,
          onBecomeHost: () {
            Navigator.pop(context);
            ModernBanner.showSuccess(context, 'Welcome to hosting! You can now create listings.');
          },
        ),
      ),
    );
  }

  void _navigateToHostDashboard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostDashboardScreen(
          repository: repository,
          authState: authState,
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              authState.logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.title),
                    subtitle:
                        item.subtitle != null ? Text(item.subtitle!) : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: item.onTap,
                  ),
                  if (index < items.length - 1) const Divider(height: 1),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsItem {
  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
}
