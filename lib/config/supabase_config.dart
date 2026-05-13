/// Supabase configuration
///
/// Replace these values with your actual Supabase project credentials.
/// You can find them in your Supabase project settings under API.
///
/// IMPORTANT: For production, consider using environment variables
/// or a secrets management solution instead of hardcoding values.
class SupabaseConfig {
  /// Your Supabase project URL
  /// Example: https://xxxxxxxxxxxxx.supabase.co
  static const String url = 'YOUR_SUPABASE_URL';

  /// Your Supabase anonymous (public) key
  /// This is safe to use in client-side code
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY';

  /// Check if Supabase is configured with real credentials
  static bool get isConfigured =>
      url != 'YOUR_SUPABASE_URL' && anonKey != 'YOUR_SUPABASE_ANON_KEY';
}
