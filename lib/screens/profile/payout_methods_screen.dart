import 'package:flutter/material.dart';

import '../../models/payout_method.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/app_settings_service.dart';
import '../../state/auth_state.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/modern_banner.dart';

/// Where the user wants to be paid.
///
/// Both roles need this and for different reasons — a host to receive their
/// earnings, a guest to receive a refund — so the screen never says "host" and
/// is reachable from every profile.
///
/// The one idea the UI has to get across, because it is unusual and people
/// will otherwise think the app is broken: **saved details can never be
/// edited**. Changing where you get paid means adding a new account and
/// removing the old one. That is not a limitation to hide behind a disabled
/// button — it is the reason nobody can quietly redirect your money — so the
/// screen says it out loud instead of offering an Edit that fails.
class PayoutMethodsScreen extends StatefulWidget {
  const PayoutMethodsScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<PayoutMethodsScreen> createState() => _PayoutMethodsScreenState();
}

class _PayoutMethodsScreenState extends State<PayoutMethodsScreen> {
  List<PayoutMethod>? _methods;
  bool _busy = false;

  String? get _userId => widget.authState.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _userId;
    if (userId == null) {
      if (mounted) setState(() => _methods = const []);
      return;
    }
    final methods = await widget.repository.fetchPayoutMethods(userId);
    if (mounted) setState(() => _methods = methods);
  }

  /// Runs a mutation, showing its refusal message rather than a generic error.
  /// The RPCs raise sentences meant for the person who caused them ("you have
  /// already added that account"), and swallowing those in favour of
  /// "Something went wrong" is how someone adds the same wallet four times.
  Future<void> _run(Future<String?> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ModernBanner.showError(context, error);
      return;
    }
    ModernBanner.showSuccess(context, success);
    await _load();
  }

  Future<void> _add() async {
    final added = await showPayoutMethodSheet(
      context,
      repository: widget.repository,
    );
    if (added == true) await _load();
  }

  Future<void> _confirmRetire(PayoutMethod method) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this account?'),
        content: Text(
          'Payouts will stop going to ${method.shortDescription}. '
          'Past payouts already sent there are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.repository.retirePayoutMethod(method.id),
      'Account removed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final methods = _methods;

    return Scaffold(
      appBar: AppBar(title: const Text('Payout methods')),
      floatingActionButton: (methods != null && methods.length < 5)
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add account'),
            )
          : null,
      body: methods == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                // Always scrollable so pull-to-refresh still works on the
                // empty state, which is exactly when someone is most likely
                // to suspect the screen simply failed to load.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _intro(theme),
                  const SizedBox(height: 20),
                  if (methods.isEmpty)
                    _empty(theme)
                  else
                    for (final m in methods) _methodCard(theme, m),
                ],
              ),
            ),
    );
  }

  Widget _intro(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_rounded,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Where we send your money',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Add the bKash, Nagad, Rocket or bank account you want to receive '
            'host earnings and refunds in. Our team checks each account '
            'against your ID before the first payout.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'For your safety, saved details can\'t be edited — add a new '
            'account and remove the old one instead.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('No payout account yet',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Add one so we know where to send your money.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _methodCard(ThemeData theme, PayoutMethod m) {
    final (statusColor, statusIcon) = switch (m.status) {
      PayoutMethodStatus.verified => (
          Colors.green.shade700,
          Icons.verified_rounded
        ),
      PayoutMethodStatus.rejected => (
          theme.colorScheme.error,
          Icons.error_rounded
        ),
      PayoutMethodStatus.pending => (
          Colors.orange.shade800,
          Icons.hourglass_top_rounded
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  child: Icon(m.channel.icon,
                      size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              m.channel.label,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (m.isDefault) ...[
                            const SizedBox(width: 8),
                            _chip(theme, 'Default', theme.colorScheme.primary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // The full number, not the mask: this is the user's own
                      // account on their own screen, and a masked number they
                      // cannot check against their wallet is a number they
                      // cannot spot a typo in.
                      Text(
                        m.accountNumber,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ]),
                      ),
                      Text(
                        m.accountName,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (m.bankName != null)
                        Text(
                          [m.bankName, m.branchName]
                              .whereType<String>()
                              .join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_busy,
                  onSelected: (value) {
                    if (value == 'default') {
                      _run(
                        () => widget.repository.setDefaultPayoutMethod(m.id),
                        'Default payout account updated.',
                      );
                    } else if (value == 'remove') {
                      _confirmRetire(m);
                    }
                  },
                  itemBuilder: (context) => [
                    if (!m.isDefault && m.status != PayoutMethodStatus.rejected)
                      const PopupMenuItem(
                        value: 'default',
                        child: Text('Make default'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(statusIcon, size: 15, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    switch (m.status) {
                      PayoutMethodStatus.verified =>
                        'Verified — ready to receive payouts',
                      PayoutMethodStatus.pending =>
                        'Awaiting review — payouts start once it\'s approved',
                      PayoutMethodStatus.rejected =>
                        m.rejectionReason ?? 'Rejected',
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Add-a-method sheet
// ───────────────────────────────────────────────────────────────────────────

/// Collects a new payout account. Resolves true when one was added.
Future<bool?> showPayoutMethodSheet(
  BuildContext context, {
  required MusafirRepository repository,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PayoutMethodSheet(repository: repository),
  );
}

class _PayoutMethodSheet extends StatefulWidget {
  const _PayoutMethodSheet({required this.repository});

  final MusafirRepository repository;

  @override
  State<_PayoutMethodSheet> createState() => _PayoutMethodSheetState();
}

class _PayoutMethodSheetState extends State<_PayoutMethodSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _bank = TextEditingController();
  final _branch = TextEditingController();
  final _routing = TextEditingController();

  late List<PayoutChannel> _channels =
      AppSettingsService.instance.payoutChannels;
  late PayoutChannel _channel = _channels.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The cached list is almost always right (settings load at startup), so
    // the sheet renders immediately from it and only corrects itself if the
    // admin has changed the offered channels since.
    AppSettingsService.instance.ensurePayoutChannels().then((channels) {
      if (!mounted || channels.isEmpty) return;
      setState(() {
        _channels = channels;
        if (!channels.contains(_channel)) _channel = channels.first;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _bank.dispose();
    _branch.dispose();
    _routing.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final isBank = _channel == PayoutChannel.bank;
    final error = await widget.repository.addPayoutMethod(
      channel: _channel,
      accountName: _name.text,
      accountNumber: _number.text,
      bankName: isBank ? _bank.text : null,
      branchName: isBank ? _branch.text : null,
      routingNumber: isBank ? _routing.text : null,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ModernBanner.showError(context, error);
      return;
    }
    Navigator.pop(context, true);
    ModernBanner.showSuccess(
      context,
      'Account added. We\'ll review it shortly.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBank = _channel == PayoutChannel.bank;

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
        child: Form(
          key: _formKey,
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
              Text('Add a payout account',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Double-check the number — for your safety it can\'t be '
                'edited afterwards.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _channels)
                    ChoiceChip(
                      label: Text(c.label),
                      avatar: Icon(c.icon, size: 18),
                      selected: _channel == c,
                      onSelected: _saving
                          ? null
                          : (_) {
                              setState(() => _channel = c);
                              // The number field means something different per
                              // channel and a half-typed wallet number is not
                              // a half-typed account number.
                              _number.clear();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              AppTextField(
                controller: _name,
                label: 'Account holder name',
                hint: 'As registered on the account',
                textCapitalization: TextCapitalization.words,
                validatorOverride: (v) => validatePayoutAccountName(v ?? ''),
              ),
              const SizedBox(height: 6),
              Text(
                'Must match the name on your ID, or the payout will be held.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _number,
                label: _channel.accountNumberLabel,
                hint: _channel.accountNumberHint,
                keyboardType:
                    isBank ? TextInputType.number : TextInputType.phone,
                validatorOverride: (v) =>
                    validatePayoutAccountNumber(_channel, v ?? ''),
              ),
              if (isBank) ...[
                const SizedBox(height: 16),
                AppTextField(
                  controller: _bank,
                  label: 'Bank name',
                  hint: 'e.g. Dutch-Bangla Bank',
                  textCapitalization: TextCapitalization.words,
                  validatorOverride: (v) => (v ?? '').trim().isEmpty
                      ? 'Enter your bank\'s name'
                      : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _branch,
                  label: 'Branch (optional)',
                  hint: 'e.g. Dhanmondi',
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _routing,
                  label: 'Routing number (optional)',
                  hint: '9 digits',
                  keyboardType: TextInputType.number,
                  validatorOverride: (v) =>
                      validatePayoutRoutingNumber(v ?? ''),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add account'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
