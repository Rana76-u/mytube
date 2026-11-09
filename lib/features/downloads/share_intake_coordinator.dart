import 'package:flutter/foundation.dart' show immutable;

import 'package:mytube/domain/services/link_extraction.dart';

/// The possible outcomes for a shared text intake.
enum ShareIntakeStatus { accepted, missingUrl, rateLimited, queueFull }

@immutable
class ShareIntakeResult {
  const ShareIntakeResult({required this.status, this.link, this.message});

  final ShareIntakeStatus status;
  final WebLink? link;
  final String? message;

  bool get isAccepted => status == ShareIntakeStatus.accepted;
  bool get hasUrl => link != null;
}

/// Coordinates raw share text into a validated [WebLink].
///
/// This keeps the intake policy in one place: untrusted text is parsed once,
/// then the result is checked against a very small rate limit and a queue cap.
/// The caller decides what to do next (for example, open the browser download
/// options flow) without duplicating parsing or quota logic.
class ShareIntakeCoordinator {
  ShareIntakeCoordinator({
    this.maxPerMinute = 5,
    this.maxQueueItems = 25,
    List<DateTime>? recentTimestamps,
  }) : _recentTimestamps = List<DateTime>.from(recentTimestamps ?? const []);

  final int maxPerMinute;
  final int maxQueueItems;
  final List<DateTime> _recentTimestamps;

  /// Evaluates a single share payload.
  ShareIntakeResult handleShareText(
    String? rawText, {
    required int queueCount,
    required DateTime now,
  }) {
    final value = rawText?.trim() ?? '';
    if (value.isEmpty) {
      return const ShareIntakeResult(status: ShareIntakeStatus.missingUrl);
    }

    final link = WebLink.parse(value);
    if (link == null) {
      return const ShareIntakeResult(status: ShareIntakeStatus.missingUrl);
    }

    _prune(now);
    if (_recentTimestamps.length >= maxPerMinute) {
      return const ShareIntakeResult(
        status: ShareIntakeStatus.rateLimited,
        message: 'Too many share links in a short time.',
      );
    }
    if (queueCount >= maxQueueItems) {
      return const ShareIntakeResult(
        status: ShareIntakeStatus.queueFull,
        message: 'The download queue is full.',
      );
    }

    _recentTimestamps.add(now);
    return ShareIntakeResult(
      status: ShareIntakeStatus.accepted,
      link: link,
      message: 'Share accepted for download.',
    );
  }

  /// Records that the share was accepted and should count against the rate
  /// limiter even when the app defers the real work.
  void rememberShare(DateTime now) {
    _prune(now);
    _recentTimestamps.add(now);
  }

  void clear() => _recentTimestamps.clear();

  void _prune(DateTime now) {
    final cutoff = now.subtract(const Duration(minutes: 1));
    _recentTimestamps.removeWhere((timestamp) => timestamp.isBefore(cutoff));
  }
}
