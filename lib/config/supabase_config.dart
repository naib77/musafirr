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
  /// Every build, a plain `flutter run -d chrome` included, talks to LIVE
  /// Supabase and, through its storage signer, the live AWS buckets. Decided
  /// 2026-10-07: the Docker stack is opt-in, not the debug default, because
  /// the user does not want to run local Supabase for day-to-day work and
  /// storage is S3-only everywhere (see `defaultStorageProvider`).
  ///
  /// So: a debug run writes to live. Opt into the local stack for one run
  /// with `--dart-define=LOCAL_STACK=true` (docs/notes/local-database.md);
  /// an explicit SUPABASE_URL always wins.
  static const bool useLocalStack = !bool.hasEnvironment('SUPABASE_URL') &&
      bool.fromEnvironment('LOCAL_STACK', defaultValue: false);

  static const String _liveUrl = 'https://bojkmonskqlhuakxhzcb.supabase.co';
  static const String _liveAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJvamttb25za3FsaHVha3hoemNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyMjI1ODUsImV4cCI6MjA5NDc5ODU4NX0.CPPAG0gh7vj5QSRMAVbcEP9FsPMjouFVIxfVJE-La7o';

  /// `supabase start`'s standard demo anon key: identical on every machine,
  /// published in the Supabase docs, and useless against any real project.
  static const String _localUrl = 'http://127.0.0.1:54321';
  static const String _localAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  /// The local signer, as `supabase functions serve --env-file
  /// supabase/functions/.env.local` serves it — the same address that file's
  /// SIGNER_PUBLIC_URL names. Only used when [useLocalStack]. (Media mirrored
  /// earlier by `tool/mirror_media_local.py` names a `deno run` signer on
  /// :8000 instead; re-mirror to repoint it.)
  static const String localSignerUrl = '$_localUrl/functions/v1/storage-signer';

  /// Your Supabase project URL
  /// Example: https://xxxxxxxxxxxxx.supabase.co
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: useLocalStack ? _localUrl : _liveUrl,
  );

  /// Your Supabase anonymous (public) key
  /// This is safe to use in client-side code
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: useLocalStack ? _localAnonKey : _liveAnonKey,
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
