/// API Keys configuration
///
/// For local development, create a file `api_keys.local.dart` with:
/// ```dart
/// const String googleMapsApiKey = 'YOUR_API_KEY_HERE';
/// ```
///
/// For production, use --dart-define:
/// ```
/// flutter build web --dart-define=GOOGLE_MAPS_API_KEY=your_key
/// ```
library;

// The Dart-side key for Google web-service calls (Directions API).
//
// Resolution: an explicit --dart-define=GOOGLE_MAPS_API_KEY=... always wins
// (release/CI builds), otherwise this default is used so a plain `flutter run`
// works with no flag — mirroring how the native map SDK reads its key from
// android/local.properties and ios/Flutter/Maps.local.xcconfig.
//
// This key is a client Maps key (already public in the README and extractable
// from any shipped binary). For real hardening, proxy Directions through a
// Supabase Edge Function so the key stays server-side.
const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: 'AIzaSyBw1uyOoZ2tS8-NS_83ov8rE3OusmmDWRM',
);
