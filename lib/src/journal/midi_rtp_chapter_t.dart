// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// Chapter T of a channel journal: the most recent N-active and C-active
/// Channel Aftertouch command (RFC 6295 A.8, Figure A.8.1).
final class MidiRtpChapterT {
  /// Creates a chapter.
  ///
  /// - [s] the S bit: false when the command is in the previous packet.
  /// - [pressure] the pressure value.
  const MidiRtpChapterT({this.s = true, required this.pressure})
    : assert(pressure >= 0 && pressure <= 0x7F);

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterT.read(MidiRtpByteReader reader) {
    final octet = reader.readUint8();
    return MidiRtpChapterT(s: octet >= 0x80, pressure: octet & 0x7F);
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() => Uint8List.fromList([(s ? 0x80 : 0) | pressure]);

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterT copyWith({bool? s, int? pressure}) =>
      MidiRtpChapterT(s: s ?? this.s, pressure: pressure ?? this.pressure);

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The channel pressure value.
  final int pressure;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 1;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterT && other.s == s && other.pressure == pressure;

  @override
  int get hashCode => Object.hash(MidiRtpChapterT, s, pressure);

  @override
  String toString() => 'MidiRtpChapterT(s: $s, pressure: $pressure)';
}
