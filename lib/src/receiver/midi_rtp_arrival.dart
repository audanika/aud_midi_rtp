// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// How a packet arrives relative to the highest sequence number received
/// before (RFC 6295 4, RFC 3550 A.1, RFC 4696 6.1).
enum MidiRtpArrival {
  /// The first packet of the stream; it is processed like a packet that
  /// ends a loss event (RFC 6295 4).
  first,

  /// The packet that follows the highest one received.
  next,

  /// A packet after a gap: the packets in between are lost.
  afterLoss,

  /// A copy of the highest packet received.
  duplicate,

  /// A packet older than the highest one received: reordered or a late
  /// duplicate; it is ignored (RFC 4696 6.1).
  late;

  // ...........................................................................
  /// Whether the packet is processed.
  bool get isAccepted => this == first || this == next || this == afterLoss;
}
