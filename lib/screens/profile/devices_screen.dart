import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/user_device.dart';
import '../../services/devices/device_registry.dart';

/// "Where you're signed in" — every device on this account, and a way to end
/// any of them.
///
/// See `docs/DEVICE_SESSIONS.md`. Two things about this screen are load-bearing
/// rather than cosmetic:
///
/// - **It exists before the cap does.** A limit with no way to see or manage
///   what is using it is a support queue: the first person to hit it can only
///   ask someone else to fix it. That is why Phase 1 is this screen and Phase 2
///   is the number.
/// - **It tells the truth about what a sign-out did.** `revoke_device` returns
///   whether a live session was actually ended, and this says "Signed out" only
///   then. A device whose session had already expired is reported differently,
///   because a security control that overstates what it did stops being
///   believed.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.registry});

  /// Injected in tests. Production uses the singleton.
  final DeviceDirectory? registry;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  DeviceDirectory get _registry => widget.registry ?? DeviceRegistry.instance;

  List<UserDevice>? _devices;
  String? _thisDeviceId;
  int _limit = 0;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final devices = await _registry.listDevices();
      final id = await _registry.deviceId();
      final limit = await _registry.deviceLimit();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _thisDeviceId = id;
        _limit = limit;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _revoke(UserDevice device) async {
    final isThisDevice = device.deviceId == _thisDeviceId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Sign out ${device.displayName}?'),
        content: Text(
          isThisDevice
              // Worth spelling out: the row for the device in your hand looks
              // exactly like the others, and tapping it logs you out here.
              ? 'This is the device you are using now. You will be signed out '
                  'and will need your phone number to sign back in.'
              : 'That device will be signed out. Signing in again on it will '
                  'need your phone number.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final endedLiveSession = await _registry.revoke(device.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            endedLiveSession
                ? '${device.displayName} signed out'
                // Not a failure, and not a sign-out either: the row is marked,
                // but there was no live session left to end.
                : '${device.displayName} was already signed out',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sign out: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Naming a device is what makes the list usable: three rows reading
  /// "Android phone" tell nobody which one to sign out. `label` is the only
  /// column the client may write (123 grants UPDATE column-wise), so this is
  /// the whole of editing.
  Future<void> _rename(UserDevice device) async {
    final name = await showDialog<String>(
      context: context,
      // The dialog owns its controller rather than taking one from here.
      // Disposing it as soon as `showDialog` returns throws "A
      // TextEditingController was used after being disposed": the route is
      // still running its exit animation, and the TextField is still built.
      builder: (_) => _RenameDialog(initial: device.label ?? ''),
    );
    if (name == null || !mounted) return;

    try {
      await _registry.rename(device.deviceId, name);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not rename: $e')));
    }
  }

  Future<void> _revokeOthers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out everywhere else?'),
        content: const Text(
          'Every device except this one will be signed out. Use this if you '
          'have lost a phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out others'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final count = await _registry.revokeOthers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count == 0
              ? 'No other devices were signed in'
              : count == 1
                  ? '1 device signed out'
                  : '$count devices signed out'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sign out: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _devices;

    return Scaffold(
      appBar: AppBar(title: const Text('Your devices')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            if (_error != null) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Could not load your devices.',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('$_error',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ],
              );
            }
            if (devices == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final active = devices.where((d) => d.isActive).toList();
            final counted = active.where((d) => d.countsTowardLimit).length;
            final past = devices.where((d) => !d.isActive).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_limit > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      // Web is excluded from the count server-side, so saying
                      // so here stops the number looking wrong to anyone who
                      // also uses the site.
                      '$counted of $_limit phones. Browsers are not counted. '
                      'Signing in on a new phone signs out the one you have '
                      'not used in the longest.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                for (final device in active)
                  _DeviceTile(
                    device: device,
                    isThisDevice: device.deviceId == _thisDeviceId,
                    onSignOut: _busy ? null : () => _revoke(device),
                    onRename: _busy ? null : () => _rename(device),
                  ),
                if (active.length > 1) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _revokeOthers,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out everywhere else'),
                  ),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Signed out',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  // Kept rather than deleted, so a device that was signed out
                  // does not simply vanish — which reads as data loss, and
                  // hides the very event the user may be looking for.
                  // Not renameable: naming a device you no longer hold is
                  // editing history, and the row is only here to be read.
                  for (final device in past)
                    _DeviceTile(
                      device: device,
                      isThisDevice: device.deviceId == _thisDeviceId,
                      onSignOut: null,
                      onRename: null,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Stateful purely so the controller lives and dies with the dialog.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this device'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'My phone',
          helperText: 'Only you can see this',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isThisDevice,
    required this.onSignOut,
    required this.onRename,
  });

  final UserDevice device;
  final bool isThisDevice;
  final VoidCallback? onSignOut;
  final VoidCallback? onRename;

  IconData get _icon => switch (device.platform) {
        'android' => Icons.phone_android,
        'ios' => Icons.phone_iphone,
        'web' => Icons.language,
        _ => Icons.devices_other,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revoked = device.revokedAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_icon),
        title: Row(
          children: [
            Flexible(
              child: Text(device.displayName, overflow: TextOverflow.ellipsis),
            ),
            if (isThisDevice) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('This device'),
                visualDensity: VisualDensity.compact,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          revoked != null
              ? 'Signed out ${_when(revoked)}'
              : 'Last used ${_when(device.lastSeenAt)}',
        ),
        onTap: onRename,
        trailing: onSignOut == null
            ? null
            : IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: onSignOut,
              ),
      ),
    );
  }

  /// Relative for anything recent, absolute beyond a week — "13 days ago" is
  /// harder to place than a date, and placing it is the whole point when a
  /// user is looking for a login they did not make.
  static String _when(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 2) return 'just now';
    if (delta.inHours < 1) return '${delta.inMinutes} minutes ago';
    if (delta.inHours < 24) {
      return '${delta.inHours} hour${delta.inHours == 1 ? '' : 's'} ago';
    }
    if (delta.inDays < 7) {
      return '${delta.inDays} day${delta.inDays == 1 ? '' : 's'} ago';
    }
    return 'on ${DateFormat('d MMM y').format(at)}';
  }
}
