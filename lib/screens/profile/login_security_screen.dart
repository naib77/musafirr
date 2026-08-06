import 'package:flutter/material.dart';

import '../../state/auth_state.dart';

/// Login & security: shows the account's login identity (phone) and its
/// verification status, and lets the user sign out.
class LoginSecurityScreen extends StatelessWidget {
  const LoginSecurityScreen({super.key, required this.authState});

  final AuthStateNotifier authState;

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(dialogContext); // close dialog
              Navigator.pop(context); // leave this screen
              authState.logout(); // app's auth listener routes to login
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = authState.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Login & security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Login method',
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: Text(user?.phone ?? '—'),
              subtitle: const Text('Phone number'),
              trailing: (user?.phoneVerified ?? false)
                  ? Chip(
                      label: const Text('Verified'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      labelStyle: TextStyle(color: theme.colorScheme.primary),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your phone number is how you sign in. To change it, contact support.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
