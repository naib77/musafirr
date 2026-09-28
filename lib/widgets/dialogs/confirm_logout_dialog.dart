import 'package:flutter/material.dart';

/// Asks before signing out, and answers whether to go ahead.
///
/// Extracted because logging out is now offered from two places — the Profile
/// tab's settings list and the desktop header's account menu — and a
/// destructive confirmation that exists twice is a confirmation that will
/// eventually only exist in one of them.
///
/// Returns false on dismissal (barrier tap, escape, back), so a caller can
/// treat "not true" as "don't".
Future<bool> confirmLogout(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Log out'),
      content: const Text('Are you sure you want to log out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  return result ?? false;
}
