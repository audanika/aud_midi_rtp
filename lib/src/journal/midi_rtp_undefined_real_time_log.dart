// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';

// #############################################################################
/// A Chapter D command log of an undefined System Real-Time command, 0xF9
/// or 0xFD (RFC 6295 B.1.1, Figure B.1.5).
///
/// The reserved LEGAL field is kept as raw octets.
final class MidiRtpUndefinedRealTimeLog {
  /// Creates a log.
  ///
  /// - [s] the S bit.
  /// - [count] the COUNT field (C): the number of commands modulo 256.
  /// - [legal] the reserved LEGAL field (L) as raw octets.
  MidiRtpUndefinedRealTimeLog({this.s = true, this.count, Iterable<int>? legal})
    : legal = legal == null
          ? null
          : Uint8List.fromList(legal.toList()).asUnmodifiableView() {
    assert(count == null || (count! >= 0 && count! <= 0xFF));
    assert(length <= 0x1F);
  }

  // ...........................................................................
  /// Reads a log at the position of [reader]; the LENGTH field bounds it.
  factory MidiRtpUndefinedRealTimeLog.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    final length = header & 0x1F;
    if (length < 1) {
      throw FormatException('Command log LENGTH $length is too small');
    }
    final body = reader.take(length - 1);
    final count = (header & 0x40) != 0 ? body.readUint8() : null;
    return MidiRtpUndefinedRealTimeLog(
      s: (header & 0x80) != 0,
      count: count,
      legal: (header & 0x20) != 0 ? body.readBytes(body.remaining) : null,
    );
  }

  // ...........................................................................
  /// Returns the encoded log.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) |
        (count != null ? 0x40 : 0) |
        (legal != null ? 0x20 : 0) |
        length,
    ?count,
    ...?legal,
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpUndefinedRealTimeLog copyWith({
    bool? s,
    int? count,
    Iterable<int>? legal,
  }) => MidiRtpUndefinedRealTimeLog(
    s: s ?? this.s,
    count: count ?? this.count,
    legal: legal ?? this.legal,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The COUNT field.
  final int? count;

  /// The reserved LEGAL field; cannot be modified.
  final Uint8List? legal;

  /// The number of encoded bytes, coded in the 5-bit LENGTH field.
  int get length => 1 + (count != null ? 1 : 0) + (legal?.length ?? 0);

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpUndefinedRealTimeLog &&
      other.s == s &&
      other.count == count &&
      MidiRtpEquality.lists(other.legal, legal);

  @override
  int get hashCode => Object.hash(s, count, MidiRtpEquality.hash(legal));

  @override
  String toString() =>
      'MidiRtpUndefinedRealTimeLog(s: $s, count: $count, '
      'legal: ${MidiRtpEquality.hex(legal)})';
}
