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

const String googleMapsApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_API_KEY',
  defaultValue: '',
);
