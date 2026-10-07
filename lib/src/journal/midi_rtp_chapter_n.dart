// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_note_log.dart';

// #############################################################################
/// Chapter N of a channel journal: the note numbers whose most recent
/// N-active command is a NoteOn (note logs, oldest first) or a NoteOff (the
/// NoteOff bitfield) (RFC 6295 A.6, Figures A.6.1 and A.6.2).
///
/// The bitfield is coded from the OFFBITS octet of the lowest to the one of
/// the highest note in [offNotes]; an empty bitfield is coded with LOW = 15
/// and HIGH = 1, or HIGH = 0 when the list holds 128 note logs.
final class MidiRtpChapterN {
  /// Creates a chapter.
  ///
  /// - [b] the B bit, the S bit of the bitfield: false when the previous
  ///   packet holds a NoteOff of the channel.
  /// - [logs] up to 128 note logs, oldest first.
  /// - [offNotes] the note numbers set in the NoteOff bitfield.
  MidiRtpChapterN({
    this.b = true,
    Iterable<MidiRtpNoteLog> logs = const [],
    Iterable<int> offNotes = const [],
  }) : logs = List.unmodifiable(logs),
       offNotes = List.unmodifiable(offNotes.toSet().toList()..sort()) {
    assert(this.logs.length <= 128);
    assert(this.logs.length < 128 || this.offNotes.isEmpty);
    assert(this.offNotes.every((n) => n >= 0 && n <= 0x7F));
  }

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterN.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final second = reader.readUint8();
    final low = second >> 4;
    final high = second & 0x0F;
    var count = first & 0x7F;
    if (count == 127 && low == 15 && high == 0) count = 128;
    if (low > high && !(low == 15 && high <= 1)) {
      throw FormatException('Illegal LOW $low and HIGH $high in Chapter N');
    }
    final logs = [for (var i = 0; i < count; i++) MidiRtpNoteLog.read(reader)];
    final offNotes = <int>[];
    for (var octet = low; octet <= high; octet++) {
      final bits = reader.readUint8();
      for (var bit = 0; bit < 8; bit++) {
        if ((bits & (0x80 >> bit)) != 0) offNotes.add(octet * 8 + bit);
      }
    }
    return MidiRtpChapterN(b: first >= 0x80, logs: logs, offNotes: offNotes);
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() {
    final low = offNotes.isEmpty ? 15 : offNotes.first >> 3;
    final high = offNotes.isEmpty
        ? (logs.length == 128 ? 0 : 1)
        : offNotes.last >> 3;
    final bits = [
      if (offNotes.isNotEmpty)
        for (var octet = low; octet <= high; octet++) 0,
    ];
    for (final note in offNotes) {
      bits[(note >> 3) - low] |= 0x80 >> (note & 7);
    }
    return Uint8List.fromList([
      (b ? 0x80 : 0) | (logs.length == 128 ? 127 : logs.length),
      low << 4 | high,
      for (final log in logs) ...log.toBytes(),
      ...bits,
    ]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterN copyWith({
    bool? b,
    Iterable<MidiRtpNoteLog>? logs,
    Iterable<int>? offNotes,
  }) => MidiRtpChapterN(
    b: b ?? this.b,
    logs: logs ?? this.logs,
    offNotes: offNotes ?? this.offNotes,
  );

  // ...........................................................................
  /// The B bit.
  final bool b;

  /// The note logs, oldest first; cannot be modified.
  final List<MidiRtpNoteLog> logs;

  /// The note numbers of the NoteOff bitfield in ascending order; cannot be
  /// modified.
  final List<int> offNotes;

  /// The number of encoded bytes.
  int get length =>
      2 +
      2 * logs.length +
      (offNotes.isEmpty ? 0 : (offNotes.last >> 3) - (offNotes.first >> 3) + 1);

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterN &&
      other.b == b &&
      MidiRtpEquality.lists(other.logs, logs) &&
      MidiRtpEquality.lists(other.offNotes, offNotes);

  @override
  int get hashCode => Object.hash(
    b,
    MidiRtpEquality.hash(logs),
    MidiRtpEquality.hash(offNotes),
  );

  @override
  String toString() =>
      'MidiRtpChapterN(b: $b, logs: $logs, offNotes: $offNotes)';
}
