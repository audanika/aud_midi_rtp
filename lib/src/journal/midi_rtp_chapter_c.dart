// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_controller_log.dart';

// #############################################################################
/// Chapter C of a channel journal: a list of controller logs in
/// oldest-first order (RFC 6295 A.3, Figure A.3.1).
///
/// With the enhanced encoding (H bit, RFC 6295 A.3.3) a controller number
/// may appear in several logs that code its most recent commands; the
/// bitfields are the same.
final class MidiRtpChapterC {
  /// Creates a chapter with the S bit [s] and one to 128 [logs].
  MidiRtpChapterC({this.s = true, required Iterable<MidiRtpControllerLog> logs})
    : logs = List.unmodifiable(logs) {
    assert(this.logs.isNotEmpty && this.logs.length <= 128);
  }

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterC.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    return MidiRtpChapterC(
      s: header >= 0x80,
      logs: [
        for (var i = 0; i <= (header & 0x7F); i++)
          MidiRtpControllerLog.read(reader),
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
  MidiRtpChapterC copyWith({bool? s, Iterable<MidiRtpControllerLog>? logs}) =>
      MidiRtpChapterC(s: s ?? this.s, logs: logs ?? this.logs);

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The controller logs, oldest first; cannot be modified.
  final List<MidiRtpControllerLog> logs;

  /// The number of encoded bytes.
  int get length => 1 + 2 * logs.length;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterC &&
      other.s == s &&
      MidiRtpEquality.lists(other.logs, logs);

  @override
  int get hashCode => Object.hash(s, MidiRtpEquality.hash(logs));

  @override
  String toString() => 'MidiRtpChapterC(s: $s, logs: $logs)';
}
