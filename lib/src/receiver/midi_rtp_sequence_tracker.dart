// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'midi_rtp_arrival.dart';

// #############################################################################
/// Tracks the 16-bit sequence numbers of a stream as 32-bit extended
/// sequence numbers that count the rollovers (RFC 3550 A.1, RFC 6295 2.1).
///
/// Each packet is classified against the highest sequence number received:
/// a forward step below 2^15 is in order or ends a loss event, a step back
/// is a late or duplicate packet. Extended numbers start at the first
/// sequence number received.
final class MidiRtpSequenceTracker {
  /// Creates a tracker that has seen no packet.
  MidiRtpSequenceTracker();

  // ...........................................................................
  /// Classifies the packet with [sequenceNumber] and returns its arrival,
  /// its extended sequence number and the number of packets lost before
  /// it.
  ({MidiRtpArrival arrival, int extended, int lost}) track(int sequenceNumber) {
    final seq = sequenceNumber & 0xFFFF;
    final highest = _highest;
    if (highest == null) {
      _highest = seq;
      return (arrival: MidiRtpArrival.first, extended: seq, lost: 0);
    }
    final step = (seq - highest) & 0xFFFF;
    if (step == 0) {
      return (arrival: MidiRtpArrival.duplicate, extended: highest, lost: 0);
    }
    if (step >= 0x8000) {
      return (
        arrival: MidiRtpArrival.late,
        extended: highest - (0x10000 - step),
        lost: 0,
      );
    }
    _highest = highest + step;
    return (
      arrival: step == 1 ? MidiRtpArrival.next : MidiRtpArrival.afterLoss,
      extended: highest + step,
      lost: step - 1,
    );
  }

  /// Forgets the stream, e.g. after a change of the synchronization
  /// source.
  void reset() => _highest = null;

  /// Returns the extended sequence number of the 16-bit [sequenceNumber]
  /// at or before [extended], e.g. of a checkpoint packet.
  static int extendBefore(int sequenceNumber, int extended) =>
      extended - ((extended - sequenceNumber) & 0xFFFF);

  // ...........................................................................
  /// The highest extended sequence number received, or null.
  int? get highest => _highest;

  // ...........................................................................
  int? _highest;
}
