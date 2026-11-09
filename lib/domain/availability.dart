import 'dart:math' as math;

import 'source.dart';

/// A catalogue estimate, not a probability or live piece availability.
class TorrentAvailability {
  TorrentAvailability(PeerCounts counts) {
    if (counts.seeds == null && counts.peers == null) return;
    final effective = (counts.seeds ?? 0) + (counts.peers ?? 0) / 4;
    final raw = math.log(1 + effective) / math.log(101);
    // Peers may share incomplete copies. Without a known seed, cap at 2/5.
    score = raw.clamp(0, (counts.seeds ?? 0) == 0 ? 0.4 : 1.0);
  }

  double? score;
  int? get bars => score == null ? null : (score! * 5).ceil();
}
