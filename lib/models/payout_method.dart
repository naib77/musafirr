import 'package:flutter/material.dart';

/// Where a user wants to be paid: a mobile-money wallet, or a bank account.
///
/// Stored as the `payout_channel` enum in Postgres using [wireName]. Which of
/// these are actually offered is an admin setting (`payout_channels_enabled`),
/// not a code decision — this enum is only the set the app knows how to
/// validate and label.
enum PayoutChannel { bkash, nagad, rocket, bank }

extension PayoutChannelX on PayoutChannel {
  /// DB/wire value — matches the Postgres enum labels exactly.
  String get wireName => name;

  String get label => switch (this) {
        PayoutChannel.bkash => 'bKash',
        PayoutChannel.nagad => 'Nagad',
        PayoutChannel.rocket => 'Rocket',
        PayoutChannel.bank => 'Bank account',
      };

  IconData get icon => switch (this) {
        PayoutChannel.bank => Icons.account_balance_rounded,
        _ => Icons.account_balance_wallet_rounded,
      };

  /// Wallets are addressed by a mobile number; a bank account is not. Almost
  /// every difference in validation, labelling and layout follows from this
  /// one distinction, so it is named once here rather than re-derived at each
  /// site with `channel == bank`.
  bool get isMobileWallet => this != PayoutChannel.bank;

  /// What to call the account number on screen. "Account number" is wrong for
  /// a wallet — people think of it as the number they'd send money to.
  String get accountNumberLabel =>
      isMobileWallet ? '$label account number' : 'Account number';

  String get accountNumberHint => isMobileWallet ? '01XXXXXXXXX' : '';
}

/// Parses a wire value, returning null for anything unknown so a channel added
/// server-side later doesn't crash an older build.
PayoutChannel? payoutChannelFromWire(String? value) {
  if (value == null) return null;
  for (final c in PayoutChannel.values) {
    if (c.wireName == value) return c;
  }
  return null;
}

/// Admin review state, mirroring the shared `verification_status` enum. The
/// database never stores 'none' for a payout method — a method is `pending`
/// from the moment it exists — but it is parsed here so an unexpected value
/// degrades to "not usable" rather than throwing.
enum PayoutMethodStatus { pending, verified, rejected }

extension PayoutMethodStatusX on PayoutMethodStatus {
  String get label => switch (this) {
        PayoutMethodStatus.pending => 'Awaiting review',
        PayoutMethodStatus.verified => 'Verified',
        PayoutMethodStatus.rejected => 'Rejected',
      };
}

PayoutMethodStatus payoutMethodStatusFromWire(String? value) => switch (value) {
      'verified' => PayoutMethodStatus.verified,
      'rejected' => PayoutMethodStatus.rejected,
      // 'pending', 'none', null, or anything unrecognised. Defaulting to
      // pending is the safe direction: only 'verified' can receive money, so
      // an unreadable status must never be the one that unlocks a payout.
      _ => PayoutMethodStatus.pending,
    };

/// A saved payout destination.
///
/// Immutable in the database as well as in Dart: there is no update path for
/// the account details, because a silently repointed payout is the single
/// most expensive thing that can happen to a marketplace account. Changing
/// where you get paid means adding a new method and retiring the old one.
@immutable
class PayoutMethod {
  const PayoutMethod({
    required this.id,
    required this.userId,
    required this.channel,
    required this.accountName,
    required this.accountNumber,
    required this.status,
    required this.isDefault,
    this.bankName,
    this.branchName,
    this.routingNumber,
    this.rejectionReason,
    this.verifiedAt,
    this.retiredAt,
    this.createdAt,
  });

  final String id;
  final String userId;
  final PayoutChannel channel;

  /// The name the account is registered in. This is what an admin checks
  /// against the NID on file before approving.
  final String accountName;

  /// Normalised: wallets are stored as local `01XXXXXXXXX`, bank accounts as
  /// digits only. Normalisation happens server-side in `add_payout_method()`
  /// so the app cannot be the reason one wallet becomes two rows.
  final String accountNumber;

  final String? bankName;
  final String? branchName;
  final String? routingNumber;

  final PayoutMethodStatus status;
  final bool isDefault;
  final String? rejectionReason;
  final DateTime? verifiedAt;
  final DateTime? retiredAt;
  final DateTime? createdAt;

  /// Retired methods are kept forever so past payouts still name a real
  /// account, but they are not shown in the user's active list.
  bool get isRetired => retiredAt != null;

  /// The only state in which money will actually move. `record_disbursement()`
  /// enforces the same rule server-side; this getter exists so the UI can say
  /// so before the user is left wondering why they haven't been paid.
  bool get canReceivePayouts =>
      status == PayoutMethodStatus.verified && !isRetired;

  /// Last four digits with the rest masked — what to show in a list. Full
  /// numbers stay on the detail view, so a shoulder-surfed list screen does
  /// not hand over an account.
  String get maskedAccountNumber => maskPayoutAccountNumber(accountNumber);

  /// One-line description for a list tile: "bKash · ••••5678".
  String get shortDescription => '${channel.label} · $maskedAccountNumber';

  factory PayoutMethod.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v as String)?.toLocal();
    return PayoutMethod(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      // An unknown channel from a newer server falls back to bank, which is
      // the one shape that carries no format promises — better a slightly
      // odd label than a crash in a list of the user's own accounts.
      channel: payoutChannelFromWire(json['channel'] as String?) ??
          PayoutChannel.bank,
      accountName: json['account_name'] as String? ?? '',
      accountNumber: json['account_number'] as String? ?? '',
      bankName: json['bank_name'] as String?,
      branchName: json['branch_name'] as String?,
      routingNumber: json['routing_number'] as String?,
      status: payoutMethodStatusFromWire(json['status'] as String?),
      isDefault: json['is_default'] as bool? ?? false,
      rejectionReason: json['rejection_reason'] as String?,
      verifiedAt: parse(json['verified_at']),
      retiredAt: parse(json['retired_at']),
      createdAt: parse(json['created_at']),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Pure helpers.
//
// These deliberately live outside the widget layer. They encode the same rules
// the database enforces, and the only way to be confident the two agree is to
// be able to test them directly against the same cases — a validation bug
// found by a widget test is a validation bug found late.
// ───────────────────────────────────────────────────────────────────────────

/// Collapses the ways a Bangladeshi mobile number gets typed into the single
/// local form the database stores: `+880 1712-345678`, `8801712345678` and
/// `01712345678` are one wallet.
///
/// Mirrors `public.normalise_bd_msisdn()`. Anything unrecognised is returned
/// as bare digits so the validator — not this function — is what rejects it.
String normaliseBdMsisdn(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (RegExp(r'^8801[3-9][0-9]{8}$').hasMatch(digits)) {
    return '0${digits.substring(digits.length - 10)}';
  }
  if (RegExp(r'^1[3-9][0-9]{8}$').hasMatch(digits)) {
    return '0$digits';
  }
  return digits;
}

/// Validates an account number for [channel], returning an error message to
/// show the user, or null when it's acceptable.
///
/// Mirrors the `payout_methods_shape` check constraint. The app validates
/// first purely so the user gets a sentence instead of a Postgres error; the
/// database remains the thing that actually decides.
String? validatePayoutAccountNumber(PayoutChannel channel, String raw) {
  if (channel.isMobileWallet) {
    final normalised = normaliseBdMsisdn(raw);
    if (normalised.isEmpty) return 'Enter your ${channel.label} number';
    if (!RegExp(r'^01[3-9][0-9]{8}$').hasMatch(normalised)) {
      return 'Enter an 11-digit Bangladeshi mobile number, e.g. 01712345678';
    }
    return null;
  }

  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 'Enter your account number';
  if (digits.length < 6 || digits.length > 20) {
    return 'A bank account number is between 6 and 20 digits';
  }
  return null;
}

/// Validates the account holder's name. Short names are rejected because this
/// field is the one an admin compares against the NID; "a" tells them nothing.
String? validatePayoutAccountName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Enter the account holder\'s name';
  if (trimmed.length < 3) return 'Enter the full name on the account';
  return null;
}

/// BEFTN routing numbers are 9 digits. Optional — an admin can settle from the
/// bank and branch name alone, and insisting on a number most people would
/// have to go and look up costs more payouts than it saves.
String? validatePayoutRoutingNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  if (digits.length != 9) return 'A routing number is 9 digits, or leave blank';
  return null;
}

/// Masks all but the last four characters: `01712345678` → `•••••••5678`.
/// Numbers of four digits or fewer are returned unchanged — there is nothing
/// left to hide, and blanking them entirely would just look broken.
String maskPayoutAccountNumber(String accountNumber) {
  final value = accountNumber.trim();
  if (value.length <= 4) return value;
  return '${'•' * (value.length - 4)}${value.substring(value.length - 4)}';
}
