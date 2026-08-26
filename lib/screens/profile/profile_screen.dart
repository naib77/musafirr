import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/support_links.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/app_settings_service.dart';
import '../../services/image_upload_service.dart';
import '../../state/auth_state.dart';
import '../../state/notification_state.dart';
import '../../widgets/avatar_upload.dart';
import '../../widgets/modern_banner.dart';
import '../host/become_host_screen.dart';
import '../host/create_listing_screen.dart';
import '../host/host_dashboard_screen.dart';
import '../host/scheduled_messages_screen.dart';
import '../notifications/notification_settings_screen.dart';
import '../safety/safety_screen.dart';
import '../verification/identity_verification_screen.dart';
import 'edit_profile_screen.dart';
import 'login_security_screen.dart';
import 'payments_payouts_screen.dart';
import 'payout_methods_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.authState,
    required this.repository,
    this.notificationState,
    this.isHostContext = false,
    this.onSwitchToHosting,
    this.onSwitchToTravelling,
    this.hostHasPendingRequests = false,
  });

  final AuthStateNotifier authState;
  final MusafirRepository repository;
  final NotificationStateNotifier? notificationState;

  /// True when this profile is shown inside the HOST portal. Guest-side profile
  /// (false) hides host tools and instead offers a link into the host portal;
  /// host-side profile (true) shows the full hosting section.
  final bool isHostContext;

  /// Switches the app into host mode (guest-profile "Switch to hosting" link).
  /// The Profile tab is the ONLY place to change modes — there is no top-level
  /// guest/host tab strip anymore.
  final VoidCallback? onSwitchToHosting;

  /// Switches the app back into guest mode (host-profile "Switch to
  /// travelling" link).
  final VoidCallback? onSwitchToTravelling;

  /// True when the user has pending booking requests on the host side —
  /// surfaces a dot on the "Switch to hosting" row so activity isn't missed
  /// while browsing as a guest.
  final bool hostHasPendingRequests;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AuthStateNotifier get authState => widget.authState;
  MusafirRepository get repository => widget.repository;

  /// Live identity verification status ('none'/'pending'/'verified'/'rejected'),
  /// null until loaded. Kept in sync as the user logs in and after they visit
  /// the verification screen.
  String? _verificationStatus;
  String? _loadedForUserId;

  /// Help / terms / privacy destinations, admin-configurable. Starts at the
  /// compiled-in defaults so the Support rows are never dead while the settings
  /// request is in flight — the same fail-open rule AppSettingsService applies.
  SupportLinks _supportLinks = SupportLinks.defaults;

  @override
  void initState() {
    super.initState();
    authState.addListener(_onAuthChanged);
    _loadVerificationStatus();
    _loadSupportLinks();
  }

  Future<void> _loadSupportLinks() async {
    // ensure-, not the plain getter: startup kicks load() off unawaited, and a
    // user who goes straight to Profile can arrive before it has landed.
    final links = await AppSettingsService.instance.ensureSupportLinks();
    if (!mounted) return;
    setState(() => _supportLinks = links);
  }

  @override
  void dispose() {
    authState.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final id = authState.currentUser?.id;
    if (id != null && id != _loadedForUserId) _loadVerificationStatus();
  }

  Future<void> _loadVerificationStatus() async {
    final user = authState.currentUser;
    if (user == null) return;
    _loadedForUserId = user.id;
    final status =
        await ImageUploadService.instance.identityVerificationStatus(user.id);
    if (!mounted) return;
    setState(() => _verificationStatus = status);
  }

  /// Subtitle for the Identity verification row, reflecting the current status.
  String _verificationSubtitle() {
    switch (_verificationStatus) {
      case 'verified':
        return 'Verified';
      case 'pending':
        return 'Under review';
      case 'rejected':
        return 'Rejected — tap to resubmit';
      default:
        return 'Verify your identity to host or book';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // No Scaffold here - main_shell.dart provides the AppBar
    return ListenableBuilder(
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
                                    style: theme.textTheme.titleLarge?.copyWith(
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
                                      color: theme.colorScheme.primaryContainer,
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
                    onTap: () => _navigateToEditProfile(context),
                  ),
                  _SettingsItem(
                    icon: Icons.verified_user_outlined,
                    title: 'Identity verification',
                    subtitle: _verificationSubtitle(),
                    onTap: () => _navigateToVerification(context, user.id),
                  ),
                  _SettingsItem(
                    icon: Icons.security_outlined,
                    title: 'Login & security',
                    onTap: () => _navigateToLoginSecurity(context),
                  ),
                  _SettingsItem(
                    icon: Icons.payment_outlined,
                    title: 'Payments & payouts',
                    onTap: () => _navigateToPayments(context),
                  ),
                  // Listed in its own right rather than only nested under
                  // Payments: this is the setting people go looking for by
                  // name ("where do I put my bKash number?"), and burying it
                  // one level down is how a host reaches payday with nowhere
                  // to be paid.
                  _SettingsItem(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Payout methods',
                    subtitle: 'bKash, Nagad, Rocket or bank account',
                    onTap: () => _navigateToPayoutMethods(context),
                  ),
                  _SettingsItem(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    onTap: () => _navigateToNotificationSettings(context),
                  ),
                  _SettingsItem(
                    icon: Icons.health_and_safety_outlined,
                    title: 'Safety',
                    subtitle: 'Emergency help, safety tips, report a problem',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SafetyScreen(repository: repository),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Hosting section.
              //
              // Guest-side profile (isHostContext == false) must NOT contain
              // host tools — it only offers a way INTO hosting: non-hosts get
              // "Become a Host", existing hosts get "Switch to hosting" which
              // flips the app into the host portal. All the actual host tools
              // (dashboard, listings, scheduled messages, …) live in the host
              // portal / host-side profile (isHostContext == true).
              _SettingsSection(
                title: 'Hosting',
                items: [
                  if (!widget.isHostContext) ...[
                    if (!user.isHost)
                      _SettingsItem(
                        icon: Icons.home_work_outlined,
                        title: 'Become a Host',
                        subtitle: 'Start earning by sharing your space',
                        onTap: () => _navigateToBecomeHost(context),
                      )
                    else if (widget.onSwitchToHosting != null)
                      _SettingsItem(
                        icon: Icons.swap_horiz,
                        title: 'Switch to hosting',
                        subtitle: widget.hostHasPendingRequests
                            ? 'New booking request waiting'
                            : 'Go to your host dashboard',
                        showDot: widget.hostHasPendingRequests,
                        onTap: widget.onSwitchToHosting!,
                      ),
                  ] else ...[
                    if (widget.onSwitchToTravelling != null)
                      _SettingsItem(
                        icon: Icons.swap_horiz,
                        title: 'Switch to travelling',
                        subtitle: 'Find & book stays as a guest',
                        onTap: widget.onSwitchToTravelling!,
                      ),
                    _SettingsItem(
                      icon: Icons.dashboard_outlined,
                      title: 'Host Dashboard',
                      subtitle: 'Manage your listings and bookings',
                      onTap: () => _navigateToHostDashboard(context),
                    ),
                    _SettingsItem(
                      icon: Icons.add_home_outlined,
                      title: 'Create New Listing',
                      onTap: () => _navigateToCreateListing(context),
                    ),
                    // Also reachable from the host dashboard. Duplicated on
                    // purpose: this is where the language of every automated
                    // guest message is chosen (English / বাংলা), and hosts
                    // looked for it under their profile settings rather than
                    // inside the dashboard's action cards. It was dropped from
                    // here when this screen was split into host and guest
                    // contexts, and its absence read as the feature being gone.
                    _SettingsItem(
                      icon: Icons.schedule_send_outlined,
                      title: 'Scheduled messages',
                      subtitle: 'Automatic guest messages, English or বাংলা',
                      onTap: () => _navigateToScheduledMessages(context),
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
                    onTap: () =>
                        _openExternalLink(context, _supportLinks.helpUrl),
                  ),
                  _SettingsItem(
                    icon: Icons.article_outlined,
                    title: 'Terms of service',
                    onTap: () =>
                        _openExternalLink(context, _supportLinks.termsUrl),
                  ),
                  _SettingsItem(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy policy',
                    onTap: () =>
                        _openExternalLink(context, _supportLinks.privacyUrl),
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
                'Musaafir v1.0.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
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

  Future<void> _navigateToVerification(
      BuildContext context, String userId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IdentityVerificationScreen(userId: userId),
      ),
    );
    // A fresh submission flips the status to 'pending' — reflect it here.
    _loadVerificationStatus();
  }

  void _navigateToBecomeHost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BecomeHostScreen(
          authState: authState,
          onBecomeHost: () {
            Navigator.pop(context);
            // Land the brand-new host straight in the host portal — with the
            // top tab strip gone there is no other visible way in yet.
            if (widget.onSwitchToHosting != null) {
              widget.onSwitchToHosting!();
            } else {
              ModernBanner.showSuccess(
                  context, 'Welcome to hosting! You can now create listings.');
            }
          },
        ),
      ),
    );
  }

  void _navigateToHostDashboard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        // HostDashboardScreen has no Scaffold of its own — it's built to be
        // embedded in the main shell (which supplies the Scaffold + header).
        // Pushed standalone it needs its own Scaffold, otherwise its Switch
        // finds no Material ancestor and the body has no bounded constraints.
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Host Dashboard')),
          body: HostDashboardScreen(
            repository: repository,
            authState: authState,
          ),
        ),
      ),
    );
  }

  void _navigateToScheduledMessages(BuildContext context) {
    // Guarded the same way the host dashboard guards it: hostId comes from the
    // signed-in user, and the templates screen has no meaning without one.
    final hostId = authState.currentUser?.id;
    if (hostId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduledMessagesScreen(hostId: hostId),
      ),
    );
  }

  void _navigateToCreateListing(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateListingScreen(
          repository: repository,
          authState: authState,
        ),
      ),
    );
  }

  void _navigateToEditProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(authState: authState),
      ),
    );
  }

  void _navigateToLoginSecurity(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoginSecurityScreen(authState: authState),
      ),
    );
  }

  void _navigateToPayoutMethods(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PayoutMethodsScreen(
          repository: repository,
          authState: authState,
        ),
      ),
    );
  }

  void _navigateToPayments(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentsPayoutsScreen(
          repository: repository,
          authState: authState,
        ),
      ),
    );
  }

  /// Opens a Terms/Privacy/Help destination in the browser or mail client.
  /// Empty config or a launch failure surfaces a graceful message rather than a
  /// broken link.
  Future<void> _openExternalLink(BuildContext context, String url) async {
    if (url.trim().isEmpty) {
      ModernBanner.showInfo(context, 'Not available yet.');
      return;
    }
    final uri = Uri.tryParse(url);
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ModernBanner.showError(context, 'Could not open the link.');
    }
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
                    leading: Badge(
                      isLabelVisible: item.showDot,
                      smallSize: 8,
                      backgroundColor: theme.colorScheme.error,
                      child: Icon(item.icon),
                    ),
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
    this.showDot = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// Shows a small red dot on the leading icon — pending activity behind
  /// this row (e.g. new booking requests behind "Switch to hosting").
  final bool showDot;
}
