import 'package:flutter/material.dart';

import '../../models/trade_licence.dart';
import '../../services/image_upload_service.dart';
import '../modern_banner.dart';

/// The optional trade-licence section of a hotel's edit form (152).
///
/// Self-contained — it loads and submits on its own, outside the form's save
/// — because the licence is not a listing field: it has its own review state,
/// and the form's dirty tracking and Save button must not wait on an admin.
///
/// Hidden entirely when the lookup fails, which is what a database without
/// 152 looks like: better no card than a card whose upload is bound to fail.
class TradeLicenceCard extends StatefulWidget {
  const TradeLicenceCard({super.key, required this.listingId, this.service});

  final String listingId;

  /// Injectable for tests; defaults to the app-wide instance.
  final ImageUploadService? service;

  @override
  State<TradeLicenceCard> createState() => _TradeLicenceCardState();
}

class _TradeLicenceCardState extends State<TradeLicenceCard> {
  ImageUploadService get _service =>
      widget.service ?? ImageUploadService.instance;

  TradeLicence? _licence;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final licence = await _service.tradeLicence(widget.listingId);
      if (mounted) setState(() => _licence = licence);
    } catch (e) {
      debugPrint('trade licence lookup failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _upload() async {
    if (_busy) return;
    final file = await _service.pickFile(
        allowedExtensions: ImageUploadService.tradeLicenceExtensions);
    if (file == null || !mounted) return;
    final number = await showDialog<String>(
      context: context,
      builder: (_) => const _NumberDialog(),
    );
    if (!mounted) return;
    setState(() => _busy = true);
    final error = await _service.submitTradeLicence(
      file: file,
      listingId: widget.listingId,
      licenceNumber: number,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ModernBanner.showError(context, error);
      return;
    }
    ModernBanner.showSuccess(context, 'Licence submitted for review');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final licence = _licence;
    if (_failed || licence == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final status = licence.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Trade licence (optional)',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          licence.summary,
          style: theme.textTheme.bodySmall?.copyWith(
            color: status == TradeLicenceStatus.rejected
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _upload,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_file),
          label: Text(status == TradeLicenceStatus.none
              ? 'Upload licence'
              : 'Replace licence'),
        ),
      ],
    );
  }
}

/// The optional licence number. Owns its controller for the reason
/// `showBlockNoteDialog` does: the route outlives the `showDialog` future.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog();

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Licence number'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: const InputDecoration(
          hintText: 'Optional',
          helperText: 'Helps the admin match the document',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
