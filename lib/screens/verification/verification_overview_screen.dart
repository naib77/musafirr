import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'identity_verification_screen.dart';
import 'nid_verification_screen.dart';

/// Identity document first, then — only while the admin requires it — a live
/// face check.
///
/// `face_required` comes from `verification_overview` (migration 144) and
/// mirrors the admin's `face_review_enabled` switch. When it is off the face
/// step is not shown at all: an approved document is the whole of
/// verification, and a card for a step nobody can start would read as a
/// requirement the guest can never meet. When the status cannot be loaded,
/// both steps stay reachable so a failed read never hides a way forward.
class VerificationOverviewScreen extends StatefulWidget {
  const VerificationOverviewScreen(
      {super.key,
      required this.userId,
      this.reason,
      this.loadStatus,
      this.openNid,
      this.openFace});
  final String userId;
  final String? reason;
  final Future<Map<String, dynamic>> Function()? loadStatus;
  final Future<void> Function()? openNid, openFace;
  @override
  State<VerificationOverviewScreen> createState() =>
      _VerificationOverviewScreenState();
}

class _VerificationOverviewScreenState
    extends State<VerificationOverviewScreen> {
  Map<String, dynamic>? _status;
  String? _error;
  bool _loading = true;
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
      final result = widget.loadStatus != null
          ? await widget.loadStatus!()
          : Map<String, dynamic>.from(await Supabase.instance.client
              .rpc('verification_overview') as Map);
      if (mounted) setState(() => _status = result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _status = null;
          _error =
              'Could not load verification status. You can open each step to check again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Older databases only send `face_enabled`; 144 made the two the same
  /// switch, so either key answers the question.
  bool get _faceRequired =>
      _status == null ||
      (_status!['face_required'] ?? _status!['face_enabled']) == true;

  /// The face step opens once a document is in review or approved, so the
  /// admin always has a document to compare the face with. A face already
  /// submitted stays openable so its status can be read.
  bool get _faceUnlocked {
    final status = _status;
    if (status == null) return true;
    return const {'pending', 'verified'}.contains(status['nid_status']) ||
        const {'pending', 'verified', 'rejected', 'retry'}
            .contains(status['face_status']);
  }

  String _label(String key) => switch (_status?[key]) {
        'verified' || 'approved' => 'Admin approved',
        'pending' => 'Pending admin review',
        'rejected' || 'retry' => 'Another submission needed',
        'none' || 'draft' || 'superseded' => 'Not submitted',
        _ => 'Status unavailable',
      };
  Future<void> _open(bool nid) async {
    final callback = nid ? widget.openNid : widget.openFace;
    if (callback != null) {
      await callback();
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => nid
              ? const NidVerificationScreen()
              : IdentityVerificationScreen(userId: widget.userId)));
    }
    if (mounted) await _load();
  }

  Widget _step(bool nid) {
    final locked = !nid && !_loading && !_faceUnlocked;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(nid ? Icons.badge_outlined : Icons.face_6_outlined,
                      size: 36, color: AppColors.brand),
                  const SizedBox(height: 12),
                  Text(
                      nid
                          ? (_faceRequired
                              ? '1. Identity document'
                              : 'Identity document')
                          : '2. Live face check',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(nid
                      ? 'NID, passport, driving license, student/admission/exam ID, or office ID.'
                      : 'Blink and turn your head, then submit for admin review.'),
                  const SizedBox(height: 12),
                  Text(_loading
                      ? 'Checking status…'
                      : locked
                          ? 'Submit your identity document first'
                          : _label(nid ? 'nid_status' : 'face_status')),
                  const SizedBox(height: 16),
                  OutlinedButton(
                      onPressed: locked ? null : () => _open(nid),
                      child: Text(
                          nid ? 'Open document review' : 'Open face review')),
                ])));
  }

  String _when() => widget.reason == null
      ? ' before you can book or host'
      : ' ${widget.reason}';

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
          title: Text(
              _faceRequired ? 'ID & face verification' : 'ID verification')),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      _faceRequired
                          ? 'Two steps. One trusted account.'
                          : 'One step. One trusted account.',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(_faceRequired
                      ? 'Submit your identity document, then complete a live face check. An admin reviews both together${_when()}.'
                      : 'An admin must approve your identity document${_when()}.'),
                  const SizedBox(height: 24),
                  if (!_faceRequired)
                    _step(true)
                  else
                    LayoutBuilder(
                        builder: (_, c) => c.maxWidth >= 720
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Expanded(child: _step(true)),
                                    const SizedBox(width: 16),
                                    Expanded(child: _step(false))
                                  ])
                            : Column(children: [
                                _step(true),
                                const SizedBox(height: 12),
                                _step(false)
                              ])),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  TextButton(
                      onPressed: _loading ? null : _load,
                      child: const Text('Refresh verification status')),
                  if (_status?['status'] == 'verified')
                    FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(_faceRequired
                            ? 'Both approved — continue'
                            : 'Approved — continue')),
                ])),
      ))));
}
