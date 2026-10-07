// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_sys_ex_log.dart';

// #############################################################################
/// System Chapter X: the System Exclusive command logs, oldest first, with
/// no header of its own (RFC 6295 B.5).
///
/// The S bit of the first log is the S bit of the chapter; the first log's
/// own "phantom" S bit follows from the first two logs (see [isSafe]).
final class MidiRtpChapterX {
  /// Creates a chapter with at least one log.
  MidiRtpChapterX({required Iterable<MidiRtpSysExLog> logs})
    : logs = List.unmodifiable(logs) {
    assert(this.logs.isNotEmpty);
  }

  // ...........................................................................
  /// Reads the logs between the position of [reader] and its end, the end
  /// of the system journal.
  factory MidiRtpChapterX.read(MidiRtpByteReader reader) {
    final logs = <MidiRtpSysExLog>[];
    do {
      logs.add(MidiRtpSysExLog.read(reader));
    } while (!reader.isAtEnd);
    return MidiRtpChapterX(logs: logs);
  }

  // ...........................................................................
  /// Returns whether the log at [index] may be skipped after the loss of a
  /// single packet: its S bit, or for the first log the phantom S bit, the
  /// OR of the first two coded S bits (RFC 6295 B.5.1).
  bool isSafe(int index) =>
      index > 0 || logs.length == 1 ? logs[index].s : logs[0].s || logs[1].s;

  /// Returns the encoded chapter.
  Uint8List toBytes() =>
      Uint8List.fromList([for (final log in logs) ...log.toBytes()]);

  /// Returns a copy with [logs] replaced.
  MidiRtpChapterX copyWith({Iterable<MidiRtpSysExLog>? logs}) =>
      MidiRtpChapterX(logs: logs ?? this.logs);

  // ...........................................................................
  /// The command logs, oldest first; cannot be modified.
  final List<MidiRtpSysExLog> logs;

  /// The S bit of the chapter.
  bool get s => logs.first.s;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterX && MidiRtpEquality.lists(other.logs, logs);

  @override
  int get hashCode => MidiRtpEquality.hash(logs);

  @override
  String toString() => 'MidiRtpChapterX(logs: $logs)';
}
