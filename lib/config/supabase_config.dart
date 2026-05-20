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
  static const String url = 'https://bojkmonskqlhuakxhzcb.supabase.co';

  /// Your Supabase anonymous (public) key
  /// This is safe to use in client-side code
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvamttb25za3FsaHVha3hoemNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyMjI1ODUsImV4cCI6MjA5NDc5ODU4NX0.CPPAG0gh7vj5QSRMAVbcEP9FsPMjouFVIxfVJE-La7o';

  /// Check if Supabase is configured with real credentials
  static bool get isConfigured =>
      url.isNotEmpty &&
      url != 'YOUR_SUPABASE_URL' &&
      anonKey.isNotEmpty &&
      anonKey != 'YOUR_SUPABASE_ANON_KEY';
}
