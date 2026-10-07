// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:math';
import 'dart:typed_data';

// #############################################################################
/// An in-memory network path for tests of RTP MIDI streams that loses,
/// duplicates and reorders packets under the control of a seeded random
/// generator.
///
/// Packets go in with [send] and come out with [receive]; [flush] also
/// releases the packets held back for reordering. Independent losses
/// happen at [lossRate]; at [burstLossRate] a burst starts that loses up to
/// [burstLength] packets in a row. Arriving packets are duplicated at
/// [duplicateRate] and held back behind up to [reorderDepth] later packets
/// at [reorderRate]. The same seed always yields the same fate for the
/// same sequence of packets.
final class MidiRtpLossyChannel {
  /// Creates a channel.
  ///
  /// - [seed] seeds the random generator; [random] replaces it.
  /// - [lossRate] the probability that a packet is lost.
  /// - [burstLossRate] the probability that a burst loss starts.
  /// - [burstLength] the largest number of packets a burst loses.
  /// - [duplicateRate] the probability that a packet arrives twice.
  /// - [reorderRate] the probability that a packet is held back.
  /// - [reorderDepth] the largest number of later packets that overtake a
  ///   held packet.
  MidiRtpLossyChannel({
    int seed = 0,
    Random? random,
    this.lossRate = 0,
    this.burstLossRate = 0,
    this.burstLength = 3,
    this.duplicateRate = 0,
    this.reorderRate = 0,
    this.reorderDepth = 3,
  }) : assert(lossRate >= 0 && lossRate <= 1),
       assert(burstLossRate >= 0 && burstLossRate <= 1),
       assert(burstLength >= 1),
       assert(duplicateRate >= 0 && duplicateRate <= 1),
       assert(reorderRate >= 0 && reorderRate <= 1),
       assert(reorderDepth >= 1),
       _random = random ?? Random(seed);

  // ...........................................................................
  /// Sends a copy of [packet] into the channel.
  void send(List<int> packet) {
    _sent++;
    for (final held in _held) {
      held.remaining--;
    }
    _ready.addAll(_held.where((h) => h.remaining <= 0).map((h) => h.packet));
    _held.removeWhere((h) => h.remaining <= 0);
    if (_burst > 0) {
      _burst--;
      _lost++;
      return;
    }
    if (_random.nextDouble() < burstLossRate) {
      _burst = _random.nextInt(burstLength);
      _lost++;
      return;
    }
    if (_random.nextDouble() < lossRate) {
      _lost++;
      return;
    }
    final copy = Uint8List.fromList(packet);
    if (_random.nextDouble() < reorderRate) {
      _held.add(_Held(copy, 1 + _random.nextInt(reorderDepth)));
      _reordered++;
    } else {
      _ready.add(copy);
    }
    if (_random.nextDouble() < duplicateRate) {
      _ready.add(Uint8List.fromList(copy));
      _duplicated++;
    }
  }

  /// Returns the packets that arrived since the last call, in arrival
  /// order.
  List<Uint8List> receive() {
    final arrived = List<Uint8List>.of(_ready);
    _ready.clear();
    return arrived;
  }

  /// Releases the packets held back for reordering and returns every
  /// packet that arrived.
  List<Uint8List> flush() {
    _ready.addAll(_held.map((h) => h.packet));
    _held.clear();
    return receive();
  }

  // ...........................................................................
  /// The probability that a packet is lost.
  final double lossRate;

  /// The probability that a burst loss starts.
  final double burstLossRate;

  /// The largest number of packets a burst loses.
  final int burstLength;

  /// The probability that a packet arrives twice.
  final double duplicateRate;

  /// The probability that a packet is held back.
  final double reorderRate;

  /// The largest number of later packets that overtake a held packet.
  final int reorderDepth;

  /// The number of packets sent into the channel.
  int get sent => _sent;

  /// The number of packets lost.
  int get lost => _lost;

  /// The number of packets that arrived twice.
  int get duplicated => _duplicated;

  /// The number of packets held back for reordering.
  int get reordered => _reordered;

  // ...........................................................................
  final Random _random;
  final List<Uint8List> _ready = [];
  final List<_Held> _held = [];
  int _burst = 0;
  int _sent = 0;
  int _lost = 0;
  int _duplicated = 0;
  int _reordered = 0;
}

// #############################################################################
class _Held {
  _Held(this.packet, this.remaining);

  final Uint8List packet;
  int remaining;
}
