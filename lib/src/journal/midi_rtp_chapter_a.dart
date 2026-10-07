// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_pressure_log.dart';

// #############################################################################
/// Chapter A of a channel journal: the most recent C-active Poly Aftertouch
/// per note number, oldest first (RFC 6295 A.9, Figure A.9.1).
final class MidiRtpChapterA {
  /// Creates a chapter with the S bit [s] and one to 128 [logs].
  MidiRtpChapterA({this.s = true, required Iterable<MidiRtpPressureLog> logs})
    : logs = List.unmodifiable(logs) {
    assert(this.logs.isNotEmpty && this.logs.length <= 128);
  }

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterA.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    return MidiRtpChapterA(
      s: header >= 0x80,
      logs: [
        for (var i = 0; i <= (header & 0x7F); i++)
          MidiRtpPressureLog.read(reader),
      ],
    );
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) | (logs.length - 1),
    for (final log in logs) ...log.toBytes(),
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterA copyWith({bool? s, Iterable<MidiRtpPressureLog>? logs}) =>
      MidiRtpChapterA(s: s ?? this.s, logs: logs ?? this.logs);

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The note logs, oldest first; cannot be modified.
  final List<MidiRtpPressureLog> logs;

  /// The number of encoded bytes.
  int get length => 1 + 2 * logs.length;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterA &&
      other.s == s &&
      MidiRtpEquality.lists(other.logs, logs);

  @override
  int get hashCode => Object.hash(s, MidiRtpEquality.hash(logs));

  @override
  String toString() => 'MidiRtpChapterA(s: $s, logs: $logs)';
}
