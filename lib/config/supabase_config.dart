/// Supabase configuration.
///
/// Both values come from `--dart-define`, falling back to the long-standing
/// project so an ordinary `flutter build` / `flutter run` behaves exactly as it
/// always has. Nothing about the default build changes.
///
/// The point of the indirection: `stage-deploy` and `production` deploy to two
/// different Cloudflare accounts but, with the URL compiled in, both served the
/// SAME Supabase project — so "production" shared its tables, its rows and its
/// auth (including any QA login bypass) with staging, and a migration hit both
/// at once. Pointing a build at a different project is now a build flag rather
/// than a code edit:
///
/// ```sh
/// flutter build web --release \
///   --dart-define=SUPABASE_URL=https://PROJECT_REF.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=THE_ANON_KEY
/// ```
///
/// `tool/build_web.sh` forwards $SUPABASE_URL / $SUPABASE_ANON_KEY when they are
/// set, and the deploy workflow feeds them from each GitHub Environment — so the
/// two targets can diverge without either build being special-cased.
///
/// The anon key is a public, client-side credential (RLS is what protects the
/// data), so compiling one in as the default leaks nothing that isn't already
/// in the shipped bundle.
class SupabaseConfig {
  /// Your Supabase project URL
  /// Example: https://xxxxxxxxxxxxx.supabase.co
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://bojkmonskqlhuakxhzcb.supabase.co',
  );

  /// Your Supabase anonymous (public) key
  /// This is safe to use in client-side code
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvamttb25za3FsaHVha3hoemNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyMjI1ODUsImV4cCI6MjA5NDc5ODU4NX0.CPPAG0gh7vj5QSRMAVbcEP9FsPMjouFVIxfVJE-La7o',
  );

  /// The project ref the build is pointed at ("bojkmonskqlhuakxhzcb"), for
  /// diagnostics — so "which database am I talking to?" is answerable from a
  /// running build instead of inferred from which URL was compiled in.
  static String get projectRef {
    final host = Uri.tryParse(url)?.host ?? '';
    final dot = host.indexOf('.');
    return dot == -1 ? host : host.substring(0, dot);
  }

  /// Check if Supabase is configured with real credentials flutter build apk --debug  flutter build apk --release
  static bool get isConfigured =>
      url.isNotEmpty &&
      url != 'YOUR_SUPABASE_URL' &&
      anonKey.isNotEmpty &&
      anonKey != 'YOUR_SUPABASE_ANON_KEY';
}
