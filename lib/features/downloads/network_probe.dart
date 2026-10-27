import 'dart:async';
import 'dart:io';

/// Best-effort "is a network reachable right now" check with no third-party
/// dependency (VP6.4).
///
/// A DNS lookup is the cheapest signal `dart:io` offers without pulling in a
/// connectivity package. This is intentionally only advisory: the pill uses it
/// to *disable a fresh download start* while offline, and the transfer itself
/// still reports the real network outcome (a failure maps to a retry state), so
/// a false "online" here is harmless and a false "offline" merely waits for the
/// next probe. Kept injectable so tests drive both branches deterministically.
Future<bool> ioOnlineProbe() async {
  try {
    final result = await InternetAddress.lookup(
      'example.com',
    ).timeout(const Duration(seconds: 3));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  } catch (_) {
    return false;
  }
}
