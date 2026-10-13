/// Strips credentials and signed-URL query strings from diagnostic text.
///
/// Used before any log sink so SEC-005 and URL-006 hold even when an
/// exception message contains a playback URL or token.
final class DiagnosticRedactor {
  const DiagnosticRedactor();

  static final RegExp _urlPattern = RegExp(
    r"""https?://[^\s'"<>\]\)]+""",
    caseSensitive: false,
  );

  static final RegExp _sensitiveAssignment = RegExp(
    r'(token|access_token|refresh_token|id_token|password|secret|'
    r'api[_-]?key|authorization)\s*[:=]\s*\S+',
    caseSensitive: false,
  );

  static final RegExp _bearer = RegExp(r'Bearer\s+\S+', caseSensitive: false);

  String redact(String input) {
    var output = input.replaceAllMapped(_urlPattern, (match) {
      return _redactUrl(match.group(0)!);
    });
    output = output.replaceAllMapped(_bearer, (_) => 'Bearer [redacted]');
    output = output.replaceAllMapped(_sensitiveAssignment, (match) {
      final raw = match.group(0)!;
      final separator = raw.contains(':') ? ':' : '=';
      final name = raw.split(RegExp(r'[:=]')).first.trim();
      return '$name$separator[redacted]';
    });
    return output;
  }

  String redactObject(Object? value) => redact('$value');

  String _redactUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) {
      return '[url]';
    }
    // Omit userInfo so user:password@host never reaches a log sink.
    final originAndPath = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
    final buffer = StringBuffer(originAndPath);
    if (uri.hasQuery) {
      buffer.write('?[redacted]');
    }
    if (uri.fragment.isNotEmpty) {
      buffer.write('#[redacted]');
    }
    return buffer.toString();
  }
}
