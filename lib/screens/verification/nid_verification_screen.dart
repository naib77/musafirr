import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../services/verification/nid_verification_service.dart';

class NidVerificationScreen extends StatefulWidget {
  const NidVerificationScreen({super.key, this.repository, this.pickImage});
  final NidVerificationRepository? repository;
  final Future<Uint8List?> Function()? pickImage;
  @override
  State<NidVerificationScreen> createState() => _NidVerificationScreenState();
}

class _NidVerificationScreenState extends State<NidVerificationScreen> {
  late final _repository = widget.repository ?? NidVerificationService();
  Uint8List? _front, _back;
  String _documentType = 'nid';
  final _number = TextEditingController();
  bool get _backRequired => _documentType == 'nid';
  bool get _complete =>
      _front != null &&
      (!_backRequired || _back != null) &&
      _number.text.trim().isNotEmpty &&
      _number.text.trim().length <= 100;
  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  String? _status, _error, _note;
  bool _loading = true, _busy = false, _consent = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.status();
      if (mounted) {
        setState(() {
          _status = result['status'] as String;
          _note = result['note'] as String?;
          final type = result['document_type'] as String?;
          if (identityDocumentTypes.containsKey(type) && _front == null) {
            _documentType = type!;
          }
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'PGRST202'
            ? 'Document review is not available yet. Please check again later.'
            : 'Could not load document status. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not load document status. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(bool front) async {
    try {
      final bytes = widget.pickImage != null
          ? await widget.pickImage!()
          : await (await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 2000,
                  imageQuality: 90))
              ?.readAsBytes();
      if (bytes == null || !mounted) return;
      NidVerificationService.imageType(bytes);
      setState(() {
        if (front) {
          _front = bytes;
        } else {
          _back = bytes;
        }
        _error = null;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not open that image. Try another JPG or PNG.');
      }
    }
  }

  Future<void> _submit() async {
    if (_busy || !_consent || !_complete) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.submit(_front!, _back,
          documentType: _documentType, documentNumber: _number.text.trim());
      if (mounted) {
        setState(() {
          _status = 'pending';
          _front = null;
          _back = null;
          _consent = false;
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'PGRST202'
            ? 'Document review is not available yet. Your submission was not confirmed.'
            : e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Submission was not confirmed. Refresh status before trying again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _side(bool front) {
    final bytes = front ? _front : _back;
    final label = front
        ? 'Front / photo page'
        : (_backRequired ? 'Back (required)' : 'Back (optional)');
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (bytes != null)
                    Image.memory(bytes,
                        height: 140,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            height: 80,
                            child: Icon(Icons.image_not_supported_outlined))),
                  if (bytes == null)
                    const SizedBox(
                        height: 80,
                        child: Icon(Icons.badge_outlined, size: 40)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(front),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                          '${bytes == null ? 'Choose' : 'Replace'} ${front ? 'front' : 'back'} image')),
                ])));
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        appBar: AppBar(title: const Text('Identity documents')),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _loading
              ? const CircularProgressIndicator()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Your ID, reviewed privately.',
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 12),
                        const Text(
                            'Choose any supported document. NID requires both sides; the back is optional for other IDs. Live face review is a separate step.'),
                        const SizedBox(height: 24),
                        if (_status == 'verified' || _status == 'pending') ...[
                          Icon(
                              _status == 'verified'
                                  ? Icons.verified_outlined
                                  : Icons.hourglass_top,
                              size: 48,
                              color: AppColors.brand),
                          const SizedBox(height: 16),
                          Text(
                              _status == 'verified'
                                  ? 'Document approved by admin'
                                  : 'Document pending admin review',
                              textAlign: TextAlign.center),
                        ] else if (_status != null) ...[
                          if (_status == 'rejected') ...[
                            const Text(
                                'Your document review was rejected or revoked. Submit your document again.'),
                            if (_note != null) Text(_note!),
                            const SizedBox(height: 16),
                          ],
                          DropdownButtonFormField<String>(
                            initialValue: _documentType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Document type'),
                            items: identityDocumentTypes.entries
                                .map((e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _documentType = value;
                                      _front = null;
                                      _back = null;
                                      _number.clear();
                                      _consent = false;
                                      _error = null;
                                    });
                                  },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                              controller: _number,
                              enabled: !_busy,
                              maxLength: 100,
                              decoration: const InputDecoration(
                                  labelText: 'Document number'),
                              onChanged: (_) => setState(() {})),
                          const SizedBox(height: 16),
                          _side(true),
                          _side(false),
                          CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _consent,
                              onChanged: _busy
                                  ? null
                                  : (v) =>
                                      setState(() => _consent = v ?? false),
                              title: const Text(
                                  'I consent to private admin review of my identity document.'),
                              subtitle: const Text(
                                  'Documents are retained under the privacy policy. Upload only your own document.')),
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: !_busy && _consent && _complete
                                  ? _submit
                                  : null,
                              child: Text(_busy
                                  ? 'Submitting…'
                                  : 'Submit document for review')),
                        ],
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        const SizedBox(height: 16),
                        TextButton(
                            onPressed: _busy ? null : _load,
                            child: const Text('Refresh document status')),
                      ])),
        ))),
      ));
}
