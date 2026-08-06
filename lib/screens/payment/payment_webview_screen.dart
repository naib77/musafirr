import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/payment/sslcommerz_service.dart';

/// Hosts the SSLCommerz gateway page in a WebView and reports the outcome by
/// watching for our own success/fail/cancel redirect URLs (the `?redirect=`
/// marker added in sslcommerz-init). Settlement itself is confirmed on the
/// server; this screen only surfaces the result and pops with a
/// [PaymentOutcome].
class PaymentWebViewScreen extends StatefulWidget {
  const PaymentWebViewScreen({super.key, required this.gatewayUrl});

  final String gatewayUrl;

  @override
  State<PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<PaymentWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  PaymentOutcome? _pendingOutcome;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final outcome = _outcomeFor(request.url);
            if (outcome != null) {
              // Let the redirect page load so the server-side handler runs,
              // then pop once it finishes.
              _pendingOutcome = outcome;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            if (_pendingOutcome != null) _finish(_pendingOutcome!);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.gatewayUrl));
  }

  /// Maps our redirect landing URLs to an outcome, or null for gateway pages.
  PaymentOutcome? _outcomeFor(String url) {
    if (url.contains('redirect=success')) return PaymentOutcome.success;
    if (url.contains('redirect=fail')) return PaymentOutcome.failed;
    if (url.contains('redirect=cancel')) return PaymentOutcome.cancelled;
    return null;
  }

  void _finish(PaymentOutcome outcome) {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(PaymentOutcome.cancelled);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Secure payment'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _finish(PaymentOutcome.cancelled),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}
