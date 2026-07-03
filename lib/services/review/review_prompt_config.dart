import 'package:shared_preferences/shared_preferences.dart';

/// How often the app may proactively remind the user to review past stays.
enum ReviewReminderFrequency {
  /// Never show the automatic review prompt.
  off,

  /// At most once every 7 days.
  weekly,

  /// At most twice a week (once every 3 days).
  twiceWeekly;

  /// Minimum gap between prompts, or null when disabled.
  Duration? get minInterval => switch (this) {
        off => null,
        weekly => const Duration(days: 7),
        twiceWeekly => const Duration(days: 3),
      };

  String get label => switch (this) {
        off => 'Off',
        weekly => 'Weekly',
        twiceWeekly => 'Twice a week',
      };

  String get description => switch (this) {
        off => 'Never remind me to review past stays',
        weekly => 'Remind me at most once a week',
        twiceWeekly => 'Remind me at most twice a week',
      };
}

/// Persisted settings controlling the automatic "How was your stay?" prompt.
///
/// The prompt is throttled: it shows at most once per [ReviewReminderFrequency]
/// interval instead of on every app open. Users can still review anytime from
/// the Trips screen.
class ReviewPromptConfig {
  ReviewPromptConfig._();

  static const _frequencyKey = 'review_prompt_frequency';
  static const _lastShownKey = 'review_prompt_last_shown_at';

  static const defaultFrequency = ReviewReminderFrequency.twiceWeekly;

  static Future<ReviewReminderFrequency> getFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_frequencyKey);
    return ReviewReminderFrequency.values
            .where((f) => f.name == stored)
            .firstOrNull ??
        defaultFrequency;
  }

  static Future<void> setFrequency(ReviewReminderFrequency frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_frequencyKey, frequency.name);
  }

  /// Whether enough time has passed since the last prompt to show it again.
  static Future<bool> shouldShowPrompt() async {
    final frequency = await getFrequency();
    final interval = frequency.minInterval;
    if (interval == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final lastShownMillis = prefs.getInt(_lastShownKey);
    if (lastShownMillis == null) return true;

    final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownMillis);
    return DateTime.now().difference(lastShown) >= interval;
  }

  /// Records that the prompt was shown, starting a new throttle window.
  static Future<void> markPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastShownKey, DateTime.now().millisecondsSinceEpoch);
  }
}
