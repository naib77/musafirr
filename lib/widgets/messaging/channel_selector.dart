import 'package:flutter/material.dart';

import '../../services/messaging/message_router.dart';

/// Widget to display and select messaging channel
class ChannelSelector extends StatelessWidget {
  const ChannelSelector({
    super.key,
    required this.selectedChannel,
    required this.availableChannels,
    required this.onChannelSelected,
    this.compact = false,
  });

  final MessagingChannel selectedChannel;
  final List<MessagingChannel> availableChannels;
  final ValueChanged<MessagingChannel> onChannelSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactChannelSelector(
        selectedChannel: selectedChannel,
        availableChannels: availableChannels,
        onChannelSelected: onChannelSelected,
      );
    }

    return _FullChannelSelector(
      selectedChannel: selectedChannel,
      availableChannels: availableChannels,
      onChannelSelected: onChannelSelected,
    );
  }
}

/// Compact channel selector (dropdown/chip style)
class _CompactChannelSelector extends StatelessWidget {
  const _CompactChannelSelector({
    required this.selectedChannel,
    required this.availableChannels,
    required this.onChannelSelected,
  });

  final MessagingChannel selectedChannel;
  final List<MessagingChannel> availableChannels;
  final ValueChanged<MessagingChannel> onChannelSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If only one channel available, just show indicator
    if (availableChannels.length <= 1) {
      return _ChannelChip(
        channel: selectedChannel,
        isSelected: true,
        onTap: null,
      );
    }

    return PopupMenuButton<MessagingChannel>(
      initialValue: selectedChannel,
      onSelected: onChannelSelected,
      tooltip: 'Select messaging channel',
      child: _ChannelChip(
        channel: selectedChannel,
        isSelected: true,
        showDropdownIndicator: true,
      ),
      itemBuilder: (context) {
        return availableChannels.map((channel) {
          final isSelected = channel == selectedChannel;

          return PopupMenuItem<MessagingChannel>(
            value: channel,
            child: Row(
              children: [
                _ChannelIcon(channel: channel, size: 20),
                const SizedBox(width: 12),
                Text(channel.displayName),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(
                    Icons.check,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
    );
  }
}

/// Full channel selector (segmented buttons/toggle style)
class _FullChannelSelector extends StatelessWidget {
  const _FullChannelSelector({
    required this.selectedChannel,
    required this.availableChannels,
    required this.onChannelSelected,
  });

  final MessagingChannel selectedChannel;
  final List<MessagingChannel> availableChannels;
  final ValueChanged<MessagingChannel> onChannelSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MessagingChannel>(
      segments: availableChannels.map((channel) {
        return ButtonSegment<MessagingChannel>(
          value: channel,
          label: Text(channel.displayName),
          icon: _ChannelIcon(channel: channel, size: 18),
        );
      }).toList(),
      selected: {selectedChannel},
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) {
          onChannelSelected(selection.first);
        }
      },
    );
  }
}

/// Channel chip widget
class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.channel,
    required this.isSelected,
    this.onTap,
    this.showDropdownIndicator = false,
  });

  final MessagingChannel channel;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool showDropdownIndicator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = isSelected
        ? _getChannelColor(channel).withValues(alpha: 0.15)
        : theme.colorScheme.surfaceContainerHighest;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? _getChannelColor(channel).withValues(alpha: 0.5)
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ChannelIcon(
                channel: channel,
                size: 16,
                color: isSelected ? _getChannelColor(channel) : null,
              ),
              const SizedBox(width: 6),
              Text(
                channel.displayName,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isSelected
                      ? _getChannelColor(channel)
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (showDropdownIndicator) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: isSelected
                      ? _getChannelColor(channel)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Channel icon widget
class _ChannelIcon extends StatelessWidget {
  const _ChannelIcon({
    required this.channel,
    this.size = 24,
    this.color,
  });

  final MessagingChannel channel;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      _getChannelIconData(channel),
      size: size,
      color: color ?? _getChannelColor(channel),
    );
  }
}

/// Channel indicator badge (shows in message bubble or conversation tile)
class ChannelIndicatorBadge extends StatelessWidget {
  const ChannelIndicatorBadge({
    super.key,
    required this.channel,
    this.size = ChannelIndicatorSize.small,
  });

  final MessagingChannel channel;
  final ChannelIndicatorSize size;

  @override
  Widget build(BuildContext context) {
    if (channel == MessagingChannel.inApp) {
      // Don't show indicator for in-app messages
      return const SizedBox.shrink();
    }

    final iconSize = size == ChannelIndicatorSize.small ? 12.0 : 16.0;
    final padding = size == ChannelIndicatorSize.small ? 2.0 : 4.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: _getChannelColor(channel).withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _getChannelIconData(channel),
        size: iconSize,
        color: _getChannelColor(channel),
      ),
    );
  }
}

enum ChannelIndicatorSize { small, medium }

/// Channel connection card (for settings/profile)
class ChannelConnectionCard extends StatelessWidget {
  const ChannelConnectionCard({
    super.key,
    required this.channel,
    required this.isConnected,
    this.identifier,
    this.onConnect,
    this.onDisconnect,
  });

  final MessagingChannel channel;
  final bool isConnected;
  final String? identifier;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channelColor = _getChannelColor(channel);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Channel icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: channelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getChannelIconData(channel),
                color: channelColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Channel info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isConnected ? identifier ?? 'Connected' : 'Not connected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isConnected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Action button
            if (isConnected)
              TextButton(
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              )
            else
              FilledButton.tonal(
                onPressed: onConnect,
                child: const Text('Connect'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Channel preferences sheet
class ChannelPreferencesSheet extends StatelessWidget {
  const ChannelPreferencesSheet({
    super.key,
    required this.preferences,
    required this.onPreferencesChanged,
    this.onConnectWhatsApp,
    this.onConnectMessenger,
  });

  final UserChannelPreferences preferences;
  final ValueChanged<UserChannelPreferences> onPreferencesChanged;
  final VoidCallback? onConnectWhatsApp;
  final VoidCallback? onConnectMessenger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Messaging Channels',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you want to receive messages',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Preferred channel selector
            Text(
              'Preferred channel',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _PreferredChannelSelector(
              selectedChannel: preferences.preferredChannel,
              availableChannels: preferences.availableChannels,
              onChannelSelected: (channel) {
                onPreferencesChanged(
                  preferences.copyWith(preferredChannel: channel),
                );
              },
            ),
            const SizedBox(height: 24),

            // Connected channels
            Text(
              'Connected channels',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // In-App (always available)
            _ChannelOptionTile(
              channel: MessagingChannel.inApp,
              isConnected: true,
              identifier: 'Always available',
            ),

            // WhatsApp
            _ChannelOptionTile(
              channel: MessagingChannel.whatsApp,
              isConnected: preferences.canUseWhatsApp,
              identifier: preferences.whatsAppNumber,
              onConnect: onConnectWhatsApp,
            ),

            // Messenger
            _ChannelOptionTile(
              channel: MessagingChannel.messenger,
              isConnected: preferences.canUseMessenger,
              identifier:
                  preferences.messengerPsid != null ? 'Connected' : null,
              onConnect: onConnectMessenger,
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PreferredChannelSelector extends StatelessWidget {
  const _PreferredChannelSelector({
    required this.selectedChannel,
    required this.availableChannels,
    required this.onChannelSelected,
  });

  final MessagingChannel selectedChannel;
  final List<MessagingChannel> availableChannels;
  final ValueChanged<MessagingChannel> onChannelSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: availableChannels.map((channel) {
        final isSelected = channel == selectedChannel;
        return _ChannelChip(
          channel: channel,
          isSelected: isSelected,
          onTap: () => onChannelSelected(channel),
        );
      }).toList(),
    );
  }
}

class _ChannelOptionTile extends StatelessWidget {
  const _ChannelOptionTile({
    required this.channel,
    required this.isConnected,
    this.identifier,
    this.onConnect,
  });

  final MessagingChannel channel;
  final bool isConnected;
  final String? identifier;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channelColor = _getChannelColor(channel);

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: channelColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getChannelIconData(channel),
          color: channelColor,
          size: 20,
        ),
      ),
      title: Text(channel.displayName),
      subtitle: Text(
        isConnected ? identifier ?? 'Connected' : 'Tap to connect',
        style: TextStyle(
          color: isConnected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isConnected
          ? Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
            )
          : Icon(
              Icons.add_circle_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
      onTap: isConnected ? null : onConnect,
    );
  }
}

// Helper functions for channel styling
IconData _getChannelIconData(MessagingChannel channel) {
  switch (channel) {
    case MessagingChannel.inApp:
      return Icons.chat_bubble_outline;
    case MessagingChannel.whatsApp:
      return Icons.phone_android; // WhatsApp icon placeholder
    case MessagingChannel.messenger:
      return Icons.message_outlined; // Messenger icon placeholder
  }
}

Color _getChannelColor(MessagingChannel channel) {
  switch (channel) {
    case MessagingChannel.inApp:
      return const Color(0xFF6750A4); // Material primary
    case MessagingChannel.whatsApp:
      return const Color(0xFF25D366); // WhatsApp green
    case MessagingChannel.messenger:
      return const Color(0xFF0084FF); // Messenger blue
  }
}
