/// The object path inside [bucket] that a stored Supabase Storage URL points
/// at, or null when the URL is not one of that bucket's objects.
///
/// This replaces the two copies of `_storagePathFromUrl` in the listing edit
/// and hotel forms, which took everything after the first `/listing-images/`
/// anywhere in the string. That kept a `?t=` cache-buster inside the path
/// (so the delete it fed missed the object) and matched any external URL
/// that merely contained the bucket name. A null here means "not ours":
/// callers keep such an image but never try to delete it, exactly as they
/// already do for external images.
///
/// Only the URL shapes Supabase hands out are recognised —
/// `/storage/v1/object/{public|sign|authenticated}/{bucket}/…` and
/// `/storage/v1/render/image/{public|sign}/{bucket}/…`. Segments are decoded,
/// so the result is the key as it was uploaded.
///
/// The S3 migration will add its own media references beside these; legacy
/// URLs keep resolving through this function for as long as rows hold them
/// (plan §8).
String? storagePathFromUrl(String url, {required String bucket}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;
  final s = uri.pathSegments;
  final start = s.indexOf('storage');
  if (start == -1 || s.length < start + 2 || s[start + 1] != 'v1') return null;
  final rest = s.sublist(start + 2);
  final int prefix;
  if (rest.length >= 2 &&
      rest[0] == 'object' &&
      const {'public', 'sign', 'authenticated'}.contains(rest[1])) {
    prefix = 2;
  } else if (rest.length >= 3 &&
      rest[0] == 'render' &&
      rest[1] == 'image' &&
      const {'public', 'sign'}.contains(rest[2])) {
    prefix = 3;
  } else {
    return null;
  }
  if (rest.length <= prefix + 1 || rest[prefix] != bucket) return null;
  final key = rest.sublist(prefix + 1);
  if (key.any((segment) => segment.isEmpty)) return null;
  return key.join('/');
}
