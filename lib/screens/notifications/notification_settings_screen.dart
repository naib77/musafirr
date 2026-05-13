import 'package:flutter/material.dart';

import '../../models/notification_preferences.dart';
import '../../state/notification_state.dart';

/// Screen for managing notification preferences
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.notificationState,
  });

  final NotificationStateNotifier notificationState;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationPreferences _preferences;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _preferences = widget.notificationState.preferences ??
        NotificationPreferences.defaultFor(
          widget.notificationState.currentUserId ?? 'unknown',
        );
  }

  void _updatePreferences(NotificationPreferences newPrefs) {
    setState(() {
      _preferences = newPrefs;
      _hasChanges = true;
    });
  }

  Future<void> _saveChanges() async {
    await widget.notificationState.updatePreferences(_preferences);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
      setState(() => _hasChanges = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _saveChanges,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        children: [
          // Global toggle
          _SectionHeader(title: 'General'),
          SwitchListTile(
            value: _preferences.globalEnabled,
            onChanged: (value) {
              _updatePreferences(_preferences.copyWith(globalEnabled: value));
            },
            title: const Text('Enable notifications'),
            subtitle: const Text('Receive all notifications from Musafir'),
            secondary: Icon(
              _preferences.globalEnabled
                  ? Icons.notifications
                  : Icons.notifications_off,
              color: _preferences.globalEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),

          if (_preferences.globalEnabled) ...[
            const Divider(),

            // Quiet Hours
            _SectionHeader(title: 'Quiet Hours'),
            SwitchListTile(
              value: _preferences.quietHours.enabled,
              onChanged: (value) {
                _updatePreferences(_preferences.copyWith(
                  quietHours: _preferences.quietHours.copyWith(enabled: value),
                ));
              },
              title: const Text('Enable quiet hours'),
              subtitle: Text(
                _preferences.quietHours.enabled
                    ? '${_formatTime(_preferences.quietHours.startTime)} - ${_formatTime(_preferences.quietHours.endTime)}'
                    : 'Pause notifications during set times',
              ),
              secondary: const Icon(Icons.bedtime),
            ),

            if (_preferences.quietHours.enabled) ...[
              ListTile(
                leading: const SizedBox(width: 24),
                title: const Text('Start time'),
                trailing: Text(
                  _formatTime(_preferences.quietHours.startTime),
                  style: theme.textTheme.bodyLarge,
                ),
                onTap: () => _selectTime(context, isStartTime: true),
              ),
              ListTile(
                leading: const SizedBox(width: 24),
                title: const Text('End time'),
                trailing: Text(
                  _formatTime(_preferences.quietHours.endTime),
                  style: theme.textTheme.bodyLarge,
                ),
                onTap: () => _selectTime(context, isStartTime: false),
              ),
              SwitchListTile(
                value: _preferences.quietHours.allowUrgent,
                onChanged: (value) {
                  _updatePreferences(_preferences.copyWith(
                    quietHours:
                        _preferences.quietHours.copyWith(allowUrgent: value),
                  ));
                },
                title: const Text('Allow urgent notifications'),
                subtitle:
                    const Text('Receive critical alerts during quiet hours'),
                secondary: const SizedBox(width: 24),
              ),
            ],

            const Divider(),

            // Category Settings
            _SectionHeader(title: 'Notification Types'),

            // Bookings
            _CategoryTile(
              icon: Icons.calendar_today,
              title: 'Bookings',
              subtitle: 'Booking requests, confirmations, reminders',
              preferences: _preferences.getForCategory('booking'),
              onChanged: (prefs) {
                _updatePreferences(_preferences.updateCategory('booking', prefs));
              },
            ),

            // Payments
            _CategoryTile(
              icon: Icons.payment,
              title: 'Payments',
              subtitle: 'Payment confirmations, refunds',
              preferences: _preferences.getForCategory('payment'),
              onChanged: (prefs) {
                _updatePreferences(_preferences.updateCategory('payment', prefs));
              },
            ),

            // Messages
            _CategoryTile(
              icon: Icons.message,
              title: 'Messages',
              subtitle: 'New messages from guests and hosts',
              preferences: _preferences.getForCategory('message'),
              onChanged: (prefs) {
                _updatePreferences(_preferences.updateCategory('message', prefs));
              },
            ),

            // Reviews
            _CategoryTile(
              icon: Icons.star,
              title: 'Reviews',
              subtitle: 'New reviews and review reminders',
              preferences: _preferences.getForCategory('review'),
              onChanged: (prefs) {
                _updatePreferences(_preferences.updateCategory('review', prefs));
              },
            ),

            // Promotions
            _CategoryTile(
              icon: Icons.local_offer,
              title: 'Promotions',
              subtitle: 'Discounts, deals, and special offers',
              preferences: _preferences.getForCategory('promotion'),
              onChanged: (prefs) {
                _updatePreferences(
                    _preferences.updateCategory('promotion', prefs));
              },
            ),

            // System
            _CategoryTile(
              icon: Icons.info,
              title: 'System',
              subtitle: 'Account updates, security alerts',
              preferences: _preferences.getForCategory('system'),
              onChanged: (prefs) {
                _updatePreferences(_preferences.updateCategory('system', prefs));
              },
            ),

            const Divider(),

            // Delivery Channels
            _SectionHeader(title: 'Delivery Channels'),
            ListTile(
              leading: const Icon(Icons.phone_android),
              title: const Text('Push Notifications'),
              subtitle: const Text('Notifications on your device'),
              trailing: Switch(
                value: _hasAnyChannelEnabled(NotificationChannel.push),
                onChanged: (value) {
                  _toggleChannelForAll(NotificationChannel.push, value);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Email'),
              subtitle: Text(_preferences.email ?? 'Not configured'),
              trailing: Switch(
                value: _hasAnyChannelEnabled(NotificationChannel.email),
                onChanged: (value) {
                  _toggleChannelForAll(NotificationChannel.email, value);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat),
              title: const Text('WhatsApp'),
              subtitle: Text(_preferences.whatsAppNumber ?? 'Not configured'),
              trailing: Switch(
                value: _hasAnyChannelEnabled(NotificationChannel.whatsApp),
                onChanged: (value) {
                  _toggleChannelForAll(NotificationChannel.whatsApp, value);
                },
              ),
            ),

            const SizedBox(height: 24),

            // Delete all notifications
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _confirmDeleteAll,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Delete all notifications',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Future<void> _selectTime(BuildContext context,
      {required bool isStartTime}) async {
    final currentTime = isStartTime
        ? _preferences.quietHours.startTime
        : _preferences.quietHours.endTime;

    final picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
    );

    if (picked != null) {
      _updatePreferences(_preferences.copyWith(
        quietHours: isStartTime
            ? _preferences.quietHours.copyWith(startTime: picked)
            : _preferences.quietHours.copyWith(endTime: picked),
      ));
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  bool _hasAnyChannelEnabled(NotificationChannel channel) {
    return _preferences.categoryPreferences.values
        .any((prefs) => prefs.channels.contains(channel));
  }

  void _toggleChannelForAll(NotificationChannel channel, bool enabled) {
    final newCategoryPrefs = <String, CategoryPreferences>{};

    for (final entry in _preferences.categoryPreferences.entries) {
      final currentChannels = Set<NotificationChannel>.from(entry.value.channels);
      if (enabled) {
        currentChannels.add(channel);
      } else {
        currentChannels.remove(channel);
      }
      newCategoryPrefs[entry.key] = entry.value.copyWith(channels: currentChannels);
    }

    _updatePreferences(_preferences.copyWith(categoryPreferences: newCategoryPrefs));
  }

  void _confirmDeleteAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all notifications?'),
        content: const Text(
          'This will permanently delete all your notifications. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.notificationState.deleteAll();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All notifications deleted')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Section header
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Category preference tile
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.preferences,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final CategoryPreferences preferences;
  final ValueChanged<CategoryPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      leading: Icon(icon, color: preferences.enabled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Switch(
        value: preferences.enabled,
        onChanged: (value) {
          onChanged(preferences.copyWith(enabled: value));
        },
      ),
      children: [
        if (preferences.enabled) ...[
          // Channels
          CheckboxListTile(
            value: preferences.channels.contains(NotificationChannel.inApp),
            onChanged: (value) {
              _toggleChannel(NotificationChannel.inApp, value ?? false);
            },
            title: const Text('In-app'),
            secondary: const Icon(Icons.notifications, size: 20),
            dense: true,
          ),
          CheckboxListTile(
            value: preferences.channels.contains(NotificationChannel.push),
            onChanged: (value) {
              _toggleChannel(NotificationChannel.push, value ?? false);
            },
            title: const Text('Push notifications'),
            secondary: const Icon(Icons.phone_android, size: 20),
            dense: true,
          ),
          CheckboxListTile(
            value: preferences.channels.contains(NotificationChannel.email),
            onChanged: (value) {
              _toggleChannel(NotificationChannel.email, value ?? false);
            },
            title: const Text('Email'),
            secondary: const Icon(Icons.email, size: 20),
            dense: true,
          ),

          // Sound & Vibration
          const Divider(indent: 16, endIndent: 16),
          SwitchListTile(
            value: preferences.sound,
            onChanged: (value) {
              onChanged(preferences.copyWith(sound: value));
            },
            title: const Text('Sound'),
            secondary: const Icon(Icons.volume_up, size: 20),
            dense: true,
          ),
          SwitchListTile(
            value: preferences.vibration,
            onChanged: (value) {
              onChanged(preferences.copyWith(vibration: value));
            },
            title: const Text('Vibration'),
            secondary: const Icon(Icons.vibration, size: 20),
            dense: true,
          ),
        ],
      ],
    );
  }

  void _toggleChannel(NotificationChannel channel, bool enabled) {
    final channels = Set<NotificationChannel>.from(preferences.channels);
    if (enabled) {
      channels.add(channel);
    } else {
      channels.remove(channel);
    }
    onChanged(preferences.copyWith(channels: channels));
  }
}
