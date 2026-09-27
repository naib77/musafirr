import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../services/verification/face_verification_service.dart';
import 'capture/face_capture_view.dart';

/// Retains the route's name so existing booking/profile entry points all move
/// to the same face-only flow. Legal identity is never claimed by this screen.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen(
      {super.key,
      required this.userId,
      this.reason,
      this.repository,
      this.capture});
  final String userId;
  final String? reason;
  final FaceVerificationRepository? repository;
  final Future<FaceCapture?> Function(BuildContext, FaceAttempt)? capture;
  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  FaceVerificationRepository get _repository =>
      widget.repository ?? FaceVerificationService.instance;
  bool _loading = true, _busy = false, _consent = false, _manual = false;
  String _status = 'none';
  bool _enabled = true;
  String? _error, _note;
  FaceAttempt? _attempt;
  FaceCapture? _capture;
  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.status();
      if (mounted) {
        setState(() {
          _status = result['status'] as String;
          _enabled = result['enabled'] != false;
          _note = result['note'] as String?;
        });
      }
    } on FaceReviewUnavailable {
      if (mounted) {
        setState(() {
          _status = 'unavailable';
          _enabled = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not load your review status. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    if (!_consent || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final attempt = await _repository.start(manual: _manual);
      if (!mounted) return;
      if (attempt.userId != widget.userId) throw StateError('Account changed');
      final capture = widget.capture != null
          ? await widget.capture!(context, attempt)
          : await Navigator.of(context).push<FaceCapture>(MaterialPageRoute(
              builder: (_) => Scaffold(
                    appBar: AppBar(
                        title: Text(
                            _manual ? 'Manual face review' : 'Face check')),
                    body: SafeArea(
                        child: FaceCaptureView(
                            attempt: attempt,
                            brand:
                                '#${AppColors.brand.toARGB32().toRadixString(16).substring(2)}',
                            onCapture: (value) {
                              if (mounted) Navigator.of(context).pop(value);
                            })),
                  )));
      if (mounted && capture != null) {
        setState(() {
          _attempt = attempt;
          _capture = capture;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not start face capture. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _attempt == null || _capture == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repository.submit(_attempt!, _capture!);
      if (mounted) {
        setState(() {
          _status = 'pending';
          _capture = null;
          _attempt = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Submission was not confirmed. Try submitting again, or retake the capture if it has expired.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: AppColors.scaffold,
          appBar: AppBar(
              title: const Text('Face review'),
              backgroundColor: AppColors.scaffold),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final intro = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.face_6_outlined,
                                size: 40, color: AppColors.brand),
                            const SizedBox(height: 24),
                            Text('A little hello.\nA safer community.',
                                style: theme.textTheme.headlineLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1,
                                    height: 1.12,
                                    color: AppColors.ink)),
                            const SizedBox(height: 16),
                            Text(
                                widget.reason == null
                                    ? 'Let our team put a face to your account.'
                                    : 'Complete face review ${widget.reason}.',
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(color: AppColors.inkMuted)),
                            const SizedBox(height: 28),
                            _detail(
                                Icons.badge_outlined,
                                'ID is a separate step',
                                'Complete document review from your verification checklist.'),
                            _detail(
                                Icons.videocam_outlined,
                                'A few simple movements',
                                'Blink and turn when prompted. No audio.'),
                            _detail(
                                Icons.person_outline,
                                'A person makes the decision',
                                'Only an admin can approve your submission.'),
                          ]);
                      final content = _panel(theme);
                      final panel = Material(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(28),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: MediaQuery.disableAnimationsOf(context)
                              ? content
                              : AnimatedSize(
                                  duration: _motion,
                                  alignment: Alignment.topCenter,
                                  child: content),
                        ),
                      );
                      return wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Expanded(child: intro),
                                  const SizedBox(width: 64),
                                  Expanded(child: panel)
                                ])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  intro,
                                  const SizedBox(height: 24),
                                  panel
                                ]);
                    }),
                  ),
          ))),
        ));
  }

  Widget _detail(IconData icon, String title, String subtitle) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.brand, size: 22),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: TextStyle(color: AppColors.inkMuted, height: 1.4))
        ]))
      ]));

  Widget _panel(ThemeData theme) {
    if (_status == 'pending' || _status == 'verified') {
      final approved = _status == 'verified';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(
            approved ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
            size: 56,
            color: AppColors.brand),
        const SizedBox(height: 20),
        Text(approved ? 'You’re approved' : 'Pending admin review',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
            approved
                ? 'Your face review is approved. Document approval is also required to book or host.'
                : 'Your capture is submitted. Our team must approve it before you can book or host.',
            textAlign: TextAlign.center),
        if (_error != null) _errorText(),
        const SizedBox(height: 24),
        if (!approved)
          OutlinedButton.icon(
              onPressed: _loadStatus,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh status')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done')),
      ]);
    }
    if (!_enabled) {
      return Column(children: [
        const Icon(Icons.schedule_outlined, size: 48),
        const SizedBox(height: 16),
        const Text(
            'Face review is not available yet. Please check again later.',
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: _loadStatus, child: const Text('Refresh status')),
      ]);
    }
    // Failed initial status reads must never look like a new, eligible account.
    if (_error != null && !_consent && _capture == null) {
      return Column(children: [
        _errorText(),
        OutlinedButton.icon(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'))
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_status == 'rejected' || _status == 'retry') ...[
        Text('Another capture is needed', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(_note ?? 'Please capture your face again for the review team.'),
        const SizedBox(height: 20),
      ],
      if (_capture != null) ...[
        ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(_capture!.selfie,
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => const SizedBox(
                    height: 140, child: Icon(Icons.face, size: 64)))),
        const SizedBox(height: 20),
        Text('Ready for review',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(_manual
            ? 'Your photo will be reviewed manually. No gesture check was completed.'
            : 'Your face movements were captured. Admin approval is still required.'),
        if (_error != null) _errorText(),
        const SizedBox(height: 24),
        FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy ? _spinner() : const Icon(Icons.send_outlined),
            label: Text(_busy ? 'Submitting…' : 'Submit for admin review')),
        TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _capture = null;
                      _attempt = null;
                      _error = null;
                    }),
            child: const Text('Retake capture')),
      ] else ...[
        Container(
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(22)),
            child: Container(
                width: 88,
                height: 112,
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.brand, width: 2),
                    borderRadius: BorderRadius.circular(60)),
                child: Icon(Icons.face_6_outlined,
                    size: 54, color: AppColors.brand))),
        const SizedBox(height: 20),
        Text(_manual ? 'Manual review photo' : 'Before you start',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
            'Find even light and remove anything covering your face. Keep your camera steady.'),
        const SizedBox(height: 16),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: _busy
                ? null
                : (value) => setState(() => _consent = value ?? false),
            title: Text(_manual
                ? 'I agree to capture a photo for private admin review.'
                : 'I agree to capture a short video and photo for private admin review.'),
            subtitle: const Text(
                'Scheduled for deletion after 30 days. No audio or ID documents.')),
        if (_error != null) _errorText(),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _consent && !_busy ? _start : null,
            icon: _busy ? _spinner() : const Icon(Icons.camera_alt_outlined),
            label: Text(_busy
                ? 'Starting…'
                : _manual
                    ? 'Take review photo'
                    : 'Start face check')),
        const SizedBox(height: 8),
        TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _manual = !_manual;
                      _consent = false;
                      _error = null;
                    }),
            child: Text(_manual
                ? 'Use guided face check'
                : 'Unable to do the movements?')),
        if (_manual)
          Text(
              'Manual review is available for accessibility or camera limitations. An admin must review the exception.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
      ],
    ]);
  }

  Widget _errorText() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Semantics(
          liveRegion: true,
          child: Text(_error!, style: TextStyle(color: AppColors.error))));
  Widget _spinner() => const SizedBox(
      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
