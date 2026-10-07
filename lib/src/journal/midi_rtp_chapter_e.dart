// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_note_extra_log.dart';

// #############################################################################
/// Chapter E of a channel journal: note command extras, release velocities
/// and reference counts of overlapping NoteOns, in oldest-first order
/// (RFC 6295 A.7, Figure A.7.1).
final class MidiRtpChapterE {
  /// Creates a chapter with the S bit [s] and one to 128 [logs].
  MidiRtpChapterE({this.s = true, required Iterable<MidiRtpNoteExtraLog> logs})
    : logs = List.unmodifiable(logs) {
    assert(this.logs.isNotEmpty && this.logs.length <= 128);
  }

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterE.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    return MidiRtpChapterE(
      s: header >= 0x80,
      logs: [
        for (var i = 0; i <= (header & 0x7F); i++)
          MidiRtpNoteExtraLog.read(reader),
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
  MidiRtpChapterE copyWith({bool? s, Iterable<MidiRtpNoteExtraLog>? logs}) =>
      MidiRtpChapterE(s: s ?? this.s, logs: logs ?? this.logs);

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The note logs, oldest first; cannot be modified.
  final List<MidiRtpNoteExtraLog> logs;

  /// The number of encoded bytes.
  int get length => 1 + 2 * logs.length;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterE &&
      other.s == s &&
      MidiRtpEquality.lists(other.logs, logs);

  @override
  int get hashCode => Object.hash(s, MidiRtpEquality.hash(logs));

  @override
  String toString() => 'MidiRtpChapterE(s: $s, logs: $logs)';
}
