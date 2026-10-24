/// The bounded browsing-session policy for the Discover feed (disc redesign
/// §18.4).
///
/// A "session" here is a period during which the feed can avoid re-showing
/// recently exposed items. The policy is intentionally simple and testable —
/// *not* an analytics subsystem (§18.6): it holds one stable id and refreshes an
/// activity timestamp, and only rolls to a fresh id when the gap since the last
/// activity exceeds [timeout].
///
/// This satisfies the §18.4 boundary rules:
/// - ordinary navigation between Discover, playback and other tabs calls
///   [touch] inside the window, so the id stays stable;
/// - a widget rebuild, a route push, or a brief background stint are not even
///   modelled as activity, so they can never *create* a session on their own;
/// - a genuinely new session begins only after a sufficiently long inactive
///   period (the configurable [timeout]), which is an implementation choice
///   rather than a hardcoded product requirement.
///
/// Session identity is local and needs no backend or account.
class DiscoverSession {
  DiscoverSession({
    this.timeout = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : assert(timeout > Duration.zero, 'timeout must be positive'),
       // ignore: prefer_initializing_formals
       _clock = clock ?? DateTime.now {
    _lastActivityAt = _clock();
    _sessionId = _newId(_lastActivityAt);
  }

  /// Inactivity gap after which [touch] starts a new session.
  final Duration timeout;

  final DateTime Function() _clock;

  late DateTime _lastActivityAt;
  late String _sessionId;
  int _sequence = 0;

  /// The id stable for the whole current session.
  String get sessionId => _sessionId;

  /// When the session last registered activity.
  DateTime get lastActivityAt => _lastActivityAt;

  /// Records a feed interaction. Returns `true` only when this call rolled the
  /// window into a brand-new session (the gap since the previous activity met
  /// [timeout]); ordinary activity refreshes the clock and returns `false`.
  bool touch() {
    final now = _clock();
    final isNewSession = now.difference(_lastActivityAt) >= timeout;
    if (isNewSession) {
      _sessionId = _newId(now);
    }
    _lastActivityAt = now;
    return isNewSession;
  }

  /// Monotonic counter keeps ids unique even when two sessions would otherwise
  /// share a millisecond timestamp (e.g. fast clock injection in tests).
  String _newId(DateTime at) =>
      'session-${at.millisecondsSinceEpoch}-${_sequence++}';
}
