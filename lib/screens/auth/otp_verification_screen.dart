import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sms_autofill/sms_autofill.dart';

import '../../core/utils/responsive.dart';
import '../../state/otp_state.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/otp_input_field.dart';

/// Screen for OTP verification
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.otpState,
  });

  final OtpStateNotifier otpState;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with CodeAutoFill {
  String _currentOtp = '';
  int _otpFieldKey = 0; // Used to reset the OTP field
  bool _autoReadStarted = false;

  @override
  void initState() {
    super.initState();
    // Android SMS Retriever: auto-read the incoming OTP. No SMS permission
    // needed; a no-op on web/iOS (manual entry still works everywhere).
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _autoReadStarted = true;
      listenForCode();
    }
  }

  /// Called by [CodeAutoFill] when the OTP SMS is auto-detected.
  @override
  void codeUpdated() {
    final detected = code ?? '';
    if (detected.length != 4 || !mounted) return;
    setState(() {
      _currentOtp = detected;
      _otpFieldKey++; // reseed OtpInputField with the detected code
    });
    _handleVerifyOtp(detected);
  }

  @override
  void dispose() {
    if (_autoReadStarted) {
      cancel();
      SmsAutoFill().unregisterListener();
    }
    super.dispose();
  }

  Future<void> _handleVerifyOtp(String otp) async {
    if (otp.length != 4) return;

    widget.otpState.clearError();
    final success = await widget.otpState.verifyOtp(otp);

    if (!success && mounted) {
      // Reset the OTP field by changing its key
      setState(() {
        _currentOtp = '';
        _otpFieldKey++;
      });

      ModernBanner.showError(context, widget.otpState.error ?? 'Verification failed');
    }
  }

  Future<void> _handleResendOtp() async {
    widget.otpState.clearError();
    final success = await widget.otpState.resendOtp();

    if (mounted) {
      // Reset the OTP field on resend
      setState(() {
        _currentOtp = '';
        _otpFieldKey++;
      });

      if (success) {
        ModernBanner.showSuccess(context, 'OTP sent successfully');
      } else {
        ModernBanner.showError(context, widget.otpState.error ?? 'Failed to resend');
      }
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => widget.otpState.editPhoneNumber(),
        ),
        title: const Text('Verify Phone'),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: Responsive.formMaxWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
          child: ListenableBuilder(
            listenable: widget.otpState,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  // Icon
                  Icon(
                    Icons.sms_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Enter verification code',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Phone number display with edit option
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Code sent to +880 ${widget.otpState.phoneNumber}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: () => widget.otpState.editPhoneNumber(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // OTP Input - use ValueKey to reset on error
                  OtpInputField(
                    key: ValueKey('otp_field_$_otpFieldKey'),
                    length: 4,
                    enabled: !widget.otpState.isLoading,
                    initialValue: _currentOtp,
                    onChanged: (value) => setState(() => _currentOtp = value),
                    onCompleted: _handleVerifyOtp,
                  ),
                  const SizedBox(height: 24),

                  // Expiry countdown
                  if (widget.otpState.expiryCountdown > 0)
                    Text(
                      'Code expires in ${_formatTime(widget.otpState.expiryCountdown)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: widget.otpState.expiryCountdown < 60
                            ? Colors.red
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 24),

                  // Verify button
                  FilledButton(
                    onPressed: widget.otpState.isLoading || _currentOtp.length != 4
                        ? null
                        : () => _handleVerifyOtp(_currentOtp),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: widget.otpState.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: 16),

                  // Resend button
                  Center(
                    child: widget.otpState.canResend
                        ? TextButton(
                            onPressed: widget.otpState.isLoading
                                ? null
                                : _handleResendOtp,
                            child: const Text('Resend Code'),
                          )
                        : Text(
                            'Resend code in ${widget.otpState.resendCountdown}s',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
          ),
        ),
      ),
    );
  }
}
