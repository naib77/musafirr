// Does a file's content match the type it was uploaded as?
//
// The client's Content-Type is a claim (plan §6); this is the evidence. It
// checks magic bytes only — enough that a renamed executable or HTML page
// cannot be committed as an "image/jpeg" in a public bucket. It is not a
// malware scanner, and decoding images is deliberately out of scope.
//
// Every type here is one some bucket's `allowed_mime_types` permits today.
// An unknown declared type is refused rather than waved through, so adding a
// type to a bucket means adding it here too.

function at(b: Uint8Array, offset: number, sig: number[]): boolean {
  if (b.length < offset + sig.length) return false;
  return sig.every((v, i) => b[offset + i] === v);
}
const ascii = (s: string) => [...s].map((c) => c.charCodeAt(0));

function isoBrand(b: Uint8Array): string | null {
  if (!at(b, 4, ascii("ftyp"))) return null;
  return String.fromCharCode(...b.subarray(8, 12));
}
const heifBrands = new Set([
  "heic",
  "heix",
  "heim",
  "heis",
  "hevc",
  "hevx",
  "mif1",
  "msf1",
]);

const OLE = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
const ZIP = [0x50, 0x4b, 0x03, 0x04];

export function contentMatches(declared: string, b: Uint8Array): boolean {
  switch (declared) {
    case "image/jpeg":
      return at(b, 0, [0xff, 0xd8, 0xff]);
    case "image/png":
      return at(b, 0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    case "image/webp":
      return at(b, 0, ascii("RIFF")) && at(b, 8, ascii("WEBP"));
    case "image/gif":
      return at(b, 0, ascii("GIF87a")) || at(b, 0, ascii("GIF89a"));
    case "image/heic":
      return heifBrands.has(isoBrand(b) ?? "");
    case "video/mp4": {
      const brand = isoBrand(b);
      return brand !== null && !heifBrands.has(brand);
    }
    case "video/webm":
      return at(b, 0, [0x1a, 0x45, 0xdf, 0xa3]);
    case "application/pdf":
      return at(b, 0, ascii("%PDF-"));
    case "application/msword":
    case "application/vnd.ms-excel":
      return at(b, 0, OLE);
    case "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
    case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
      return at(b, 0, ZIP);
    case "text/plain":
      // No signature exists; a NUL byte in the first 8 KiB means binary.
      return !b.subarray(0, 8192).includes(0);
    default:
      return false;
  }
}
