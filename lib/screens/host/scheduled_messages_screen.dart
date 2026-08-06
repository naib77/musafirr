import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../models/message_template.dart';
import '../../repositories/supabase_message_template_repository.dart';
import '../../widgets/modern_banner.dart';

/// Host settings for automatic guest messages (Airbnb-style scheduled
/// messages): booking confirmed, before check-in, and after checkout.
class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key, required this.hostId});

  final String hostId;

  @override
  State<ScheduledMessagesScreen> createState() =>
      _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  final _repository = SupabaseMessageTemplateRepository.instance;
  List<MessageTemplate>? _templates;
  MessageLanguage _language = MessageLanguage.en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final templates = await _repository.templatesFor(widget.hostId);
    final language = await _repository.languageFor(widget.hostId);
    if (mounted) {
      setState(() {
        _templates = templates;
        _language = language;
      });
    }
  }

  Future<void> _setLanguage(MessageLanguage language) async {
    if (language == _language) return;
    final previous = _language;
    setState(() => _language = language);
    final saved = await _repository.setLanguage(widget.hostId, language);
    if (!saved && mounted) {
      setState(() => _language = previous);
      ModernBanner.showError(context, 'Could not save. Please try again.');
    }
  }

  Future<void> _toggle(MessageTemplate template, bool enabled) async {
    final updated = template.copyWith(enabled: enabled);
    setState(() {
      _templates = [
        for (final t in _templates!)
          t.trigger == template.trigger ? updated : t,
      ];
    });
    final saved = await _repository.save(updated);
    if (!saved && mounted) {
      ModernBanner.showError(context, 'Could not save. Please try again.');
      _load();
    }
  }

  Future<void> _edit(MessageTemplate template) async {
    final result = await Navigator.push<MessageTemplate>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            _TemplateEditorScreen(template: template, language: _language),
      ),
    );
    if (result == null) return;

    setState(() {
      _templates = [
        for (final t in _templates!) t.trigger == result.trigger ? result : t,
      ];
    });
    final saved = await _repository.save(result);
    if (!mounted) return;
    if (saved) {
      ModernBanner.showSuccess(context, 'Scheduled message saved');
    } else {
      ModernBanner.showError(context, 'Could not save. Please try again.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = _templates;

    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled messages')),
      body: ResponsiveCenter(
        maxWidth: 760,
        child: templates == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Messages sent to your guests automatically at each stage '
                    'of their stay. Variables like {{guest_name}} are filled '
                    'in per booking.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Language: applied automatically to every automated message
                  // sent to guests.
                  Text('Language', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<MessageLanguage>(
                    segments: const [
                      ButtonSegment(
                        value: MessageLanguage.en,
                        label: Text('English'),
                      ),
                      ButtonSegment(
                        value: MessageLanguage.bn,
                        label: Text('বাংলা'),
                      ),
                    ],
                    selected: {_language},
                    onSelectionChanged: (selection) =>
                        _setLanguage(selection.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Guests receive these messages in the selected language. '
                    'Messages you edit yourself are sent exactly as written.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),

                  for (final template in templates) ...[
                    _TemplateCard(
                      template: template,
                      language: _language,
                      onToggle: (enabled) => _toggle(template, enabled),
                      onEdit: () => _edit(template),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.language,
    required this.onToggle,
    required this.onEdit,
  });

  final MessageTemplate template;
  final MessageLanguage language;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  IconData get _icon => switch (template.trigger) {
        MessageTemplateTrigger.bookingConfirmed => Icons.celebration_outlined,
        MessageTemplateTrigger.checkIn => Icons.vpn_key_outlined,
        MessageTemplateTrigger.checkOut => Icons.waving_hand_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.trigger.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          template.trigger == MessageTemplateTrigger.checkIn
                              ? 'Sent ${template.leadDays} day(s) before '
                                  'arrival'
                              : template.trigger.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(value: template.enabled, onChanged: onToggle),
                ],
              ),
              if (template.enabled) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    MessageTemplate.resolveContent(template, language),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen editor for one template: content with variable chips, and the
/// lead-days picker for the pre-check-in message.
class _TemplateEditorScreen extends StatefulWidget {
  const _TemplateEditorScreen({required this.template, required this.language});

  final MessageTemplate template;
  final MessageLanguage language;

  @override
  State<_TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<_TemplateEditorScreen> {
  late final TextEditingController _controller;
  late int _leadDays;

  @override
  void initState() {
    super.initState();
    // Seed with what the guest would actually receive in the chosen language:
    // an un-customized template shows the language default, a custom one shows
    // the host's own text.
    _controller = TextEditingController(
      text: MessageTemplate.resolveContent(widget.template, widget.language),
    );
    _leadDays = widget.template.leadDays;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _insertVariable(String variable) {
    final selection = _controller.selection;
    final text = _controller.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, variable),
      selection: TextSelection.collapsed(offset: start + variable.length),
    );
  }

  void _save() {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      ModernBanner.showError(context, 'The message cannot be empty.');
      return;
    }
    Navigator.pop(
      context,
      widget.template.copyWith(content: content, leadDays: _leadDays),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCheckIn = widget.template.trigger == MessageTemplateTrigger.checkIn;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template.trigger.label),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.template.trigger.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (isCheckIn) ...[
            Row(
              children: [
                Expanded(
                  child: Text('Send before arrival',
                      style: theme.textTheme.titleSmall),
                ),
                DropdownButton<int>(
                  value: _leadDays,
                  onChanged: (value) {
                    if (value != null) setState(() => _leadDays = value);
                  },
                  items: [
                    for (var days = 0; days <= 7; days++)
                      DropdownMenuItem(
                        value: days,
                        child: Text(
                          days == 0 ? 'On arrival day' : '$days day(s)',
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _controller,
            maxLines: 14,
            minLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Write your message…',
            ),
          ),
          const SizedBox(height: 12),
          Text('Insert a variable', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final variable in MessageTemplate.variables)
                ActionChip(
                  label: Text(variable),
                  onPressed: () => _insertVariable(variable),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              _controller.text = MessageTemplate.defaultContentFor(
                widget.template.trigger,
                language: widget.language,
              );
            },
            icon: const Icon(Icons.restore),
            label: const Text('Reset to default'),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
