import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'identity_verification_screen.dart';
import 'nid_verification_screen.dart';

/// Keep both entry points available even when one review is pending or disabled.
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

  Widget _step(bool nid) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(nid ? Icons.badge_outlined : Icons.face_6_outlined,
                size: 36, color: AppColors.brand),
            const SizedBox(height: 12),
            Text(nid ? '1. Identity document' : '2. Live face check',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(nid
                ? 'NID, passport, driving license, student/admission/exam ID, or office ID.'
                : 'Blink and turn your head, then submit for admin review.'),
            const SizedBox(height: 12),
            Text(_loading
                ? 'Checking status…'
                : _label(nid ? 'nid_status' : 'face_status')),
            if (!nid && _status?['face_enabled'] == false)
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('New face captures are not available yet.')),
            const SizedBox(height: 16),
            OutlinedButton(
                onPressed: () => _open(nid),
                child: Text(nid ? 'Open document review' : 'Open face review')),
          ])));
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: const Text('ID & face verification')),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Two steps. One trusted account.',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(
                      'An admin must approve both your identity document and face capture${widget.reason == null ? ' before booking or hosting' : ' ${widget.reason}'}. Completing one does not approve the other.'),
                  const SizedBox(height: 24),
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
                        child: const Text('Both approved — continue')),
                ])),
      ))));
}
