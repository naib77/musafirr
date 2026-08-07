import 'package:flutter/material.dart';

import '../repositories/musafir_repository.dart';

/// Bottom sheet to report a listing / user / booking to the safety team
/// (rows land in the `reports` table; admins triage from the portal).
/// When [reportedUserId] is provided the reporter can also block that user.
Future<void> showReportSheet(
  BuildContext context, {
  required MusafirRepository repository,
  String? reportedUserId,
  String? listingId,
  String? bookingId,
  String? subjectLabel,
  bool offerBlock = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ReportSheet(
      repository: repository,
      reportedUserId: reportedUserId,
      listingId: listingId,
      bookingId: bookingId,
      subjectLabel: subjectLabel,
      offerBlock: offerBlock && reportedUserId != null,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.repository,
    required this.reportedUserId,
    required this.listingId,
    required this.bookingId,
    required this.subjectLabel,
    required this.offerBlock,
  });

  final MusafirRepository repository;
  final String? reportedUserId;
  final String? listingId;
  final String? bookingId;
  final String? subjectLabel;
  final bool offerBlock;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _categories = [
    ('safety', 'Safety concern'),
    ('fraud', 'Scam or fraud'),
    ('inappropriate', 'Inappropriate behaviour'),
    ('listing_issue', 'Listing problem'),
    ('other', 'Something else'),
  ];

  String? _category;
  final _detailsController = TextEditingController();
  bool _alsoBlock = false;
  bool _submitting = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final category = _category;
    if (category == null) return;
    setState(() => _submitting = true);

    final ok = await widget.repository.submitReport(
      reportedUserId: widget.reportedUserId,
      listingId: widget.listingId,
      bookingId: widget.bookingId,
      category: category,
      details: _detailsController.text,
    );
    if (ok && _alsoBlock && widget.reportedUserId != null) {
      await widget.repository.blockUser(widget.reportedUserId!);
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Report submitted — our team will review it.'
            : 'Could not submit the report. Please try again.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.subjectLabel == null
                  ? 'Report a problem'
                  : 'Report "${widget.subjectLabel}"',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Your report is confidential — the other party is not told '
              'who reported them.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories
                  .map((c) => ChoiceChip(
                        label: Text(c.$2),
                        selected: _category == c.$1,
                        onSelected: (_) => setState(() => _category = c.$1),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _detailsController,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'What happened?',
                hintText: 'Tell us what happened (optional but helpful)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (widget.offerBlock) ...[
              CheckboxListTile(
                value: _alsoBlock,
                onChanged: (v) => setState(() => _alsoBlock = v ?? false),
                title: const Text('Also block this user'),
                subtitle: const Text(
                    'You won\'t see their listings or messages anymore'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: (_category == null || _submitting) ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit report'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
