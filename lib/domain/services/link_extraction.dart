import 'package:flutter/foundation.dart' show immutable;

/// Free-text link handling for the link downloader (ARCHITECTURE §15.1,
/// DL1.1).
///
/// Text reaching this code — a share, the clipboard, a deep link, a backup
/// restore — is **untrusted** (AGENTS: "argument safety"). These helpers only
/// *recognise* a first `http(s)` URL and describe it safely for display; they
/// never fetch, never build engine arguments, and never expose a query string
/// (signed URLs and tracking params may carry secrets). The validated [Uri]
/// on [WebLink] is the single gate every downstream layer must go through.

/// Maximum accepted length, in characters, of an extracted URL. A longer
/// token is treated as not-a-link rather than carried onward: real page URLs
/// stay well under this, and an absurd token is a sign of paste garbage or an
/// argument-injection attempt (ARCHITECTURE §15.11).
const int kMaxUrlLength = 2048;

/// Longest path segment [describeLinkForDisplay] shows before truncating.
const int _maxDisplayPath = 32;

// Schemes this feature will ever accept. Anything else (`javascript:`,
// `file:`, `data:`, ...) is rejected even if it superficially looks like a
// link, so a crafted string can never smuggle a non-web scheme downstream.
final RegExp _urlPattern = RegExp(
  r'''(?<scheme>https?)://[^\s<>"']+''',
  caseSensitive: false,
);

/// Characters that are almost always sentence punctuation rather than part of
/// a URL when they sit at the very end of a match.
const String _trailingPunctuation = '.,;:!?\u00B4\u2019\'"`';

/// Extracts the first `http(s)` URL from arbitrary [text], or `null` when none
/// is present.
///
/// Trailing sentence punctuation and unmatched closing brackets are trimmed
/// (so `"see https://x.test/a)!"` yields `https://x.test/a`), the scheme is
/// matched case-insensitively, and any URL longer than [kMaxUrlLength] is
/// discarded. Non-web schemes are never returned because the pattern only
/// matches `http`/`https`.
String? extractFirstHttpUrl(String text) {
  for (final match in _urlPattern.allMatches(text)) {
    final candidate = _trimTrailing(match.group(0)!);
    if (candidate.length > kMaxUrlLength) continue;
    if (_asValidatedUri(candidate) != null) return candidate;
  }
  return null;
}

/// A recognised web link plus the durable, validated URL it resolved to
/// (DL1.1).
///
/// [original] keeps the raw input for logging/redaction context; [url] is the
/// validated `http(s)` URI that every downstream layer must use. Value type:
/// equality is on the canonical [url] so two inputs pointing at the same page
/// compare equal.
@immutable
class WebLink {
  const WebLink._(this.original, this.url);

  /// Builds a [WebLink] from arbitrary [input], or `null` when the input
  /// contains no valid `http(s)` URL.
  static WebLink? parse(String input) {
    final found = extractFirstHttpUrl(input);
    if (found == null) return null;
    final uri = _asValidatedUri(found);
    if (uri == null) return null;
    return WebLink._(input, uri);
  }

  /// The raw text the link was extracted from (may contain surrounding prose).
  final String original;

  /// The validated, scheme-checked URL. Never a stream/signed URL — this is
  /// the canonical page URL the extractor will re-resolve on demand (§15.2).
  final Uri url;

  /// Lower-cased host, e.g. `youtu.be`. Never includes query or fragment.
  String get host => url.host.toLowerCase();

  /// Privacy-safe, one-line description: host plus a shortened path, with the
  /// query and fragment always dropped (§15.11 — never surface signed params).
  String get displayDescription => describeLinkForDisplay(this);

  @override
  bool operator ==(Object other) =>
      other is WebLink &&
      other.url.scheme == url.scheme &&
      other.url.toString() == url.toString();

  @override
  int get hashCode => Object.hash(url.scheme, url.toString());

  @override
  String toString() => 'WebLink(${describeLinkForDisplay(this)})';
}

/// Renders a [link] for display: host plus a bounded path, never the query or
/// fragment. Shared by the clipboard prompt, the share sheet and download
/// rows so a signed URL's secret parameters are never shown to the user or
/// written to a log.
String describeLinkForDisplay(WebLink link) {
  final uri = link.url;
  final path = uri.path;
  final String clipped;
  if (path.length > _maxDisplayPath) {
    clipped = '${path.substring(0, _maxDisplayPath)}\u2026';
  } else {
    clipped = path;
  }
  final buffer = StringBuffer(link.host);
  if (clipped.isNotEmpty && clipped != '/') {
    buffer.write(clipped);
  }
  return buffer.toString();
}

/// Parses [candidate] and returns it only when it is a well-formed `http(s)`
/// URL with a host. This is the one place scheme/host validation happens so
/// every entry point behaves identically.
Uri? _asValidatedUri(String candidate) {
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// Strips trailing sentence punctuation and any closing bracket that has no
/// matching opener inside the URL, repeating until the token is stable.
String _trimTrailing(String raw) {
  var value = raw;
  while (value.isNotEmpty) {
    final last = value[value.length - 1];
    if (_trailingPunctuation.contains(last)) {
      value = value.substring(0, value.length - 1);
      continue;
    }
    // A trailing bracket/brace is kept only when its opener is present in the
    // URL (e.g. `.../Foo_(bar)`); an unbalanced one came from surrounding
    // prose like `(see https://x.test/a)` and is dropped.
    final opener = _openerFor(last);
    if (opener != null && _count(value, last) > _count(value, opener)) {
      value = value.substring(0, value.length - 1);
      continue;
    }
    break;
  }
  return value;
}

/// The matching opener for a closing bracket/brace/paren, else `null`.
String? _openerFor(String char) => switch (char) {
  ')' => '(',
  ']' => '[',
  '}' => '{',
  _ => null,
};

int _count(String value, String char) {
  var n = 0;
  for (final unit in value.codeUnits) {
    if (unit == char.codeUnitAt(0)) n++;
  }
  return n;
}
