// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The positions of a System Exclusive command or segment in the MIDI list
/// with their head and tail status octets (RFC 6295 3.2, Figure 5).
enum MidiRtpSysExKind {
  /// A whole command: 0xF0, data, 0xF7 (or 0xF5 for a dropped 0xF7).
  complete(0xF0, 0xF7),

  /// The first segment: 0xF0, data, 0xF0.
  first(0xF0, 0xF0),

  /// A middle segment: 0xF7, data, 0xF0.
  middle(0xF7, 0xF0),

  /// The last segment: 0xF7, data, 0xF7 (or 0xF5 for a dropped 0xF7).
  last(0xF7, 0xF7),

  /// The cancel sublist: 0xF7, 0xF4, without data.
  cancel(0xF7, 0xF4);

  /// Creates a kind with its [head] and [tail] status octets.
  const MidiRtpSysExKind(this.head, this.tail);

  // ...........................................................................
  /// The status octet that opens the segment.
  final int head;

  /// The status octet that closes the segment when no 0xF7 was dropped.
  final int tail;

  /// Whether the segment ends a command, completed or cancelled.
  bool get endsCommand => this == complete || this == last || this == cancel;

  /// Whether the segment starts a command.
  bool get startsCommand => this == complete || this == first;

  // ...........................................................................
  /// The tail octet that replaces 0xF7 when the source dropped the 0xF7
  /// (RFC 6295 3.2).
  static const int droppedF7Tail = 0xF5;
}
