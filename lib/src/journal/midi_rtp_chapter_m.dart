// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_parameter_log.dart';

// #############################################################################
/// Chapter M of a channel journal: the state of the RPN/NRPN parameter
/// system and one log per recently changed parameter, oldest transaction
/// first (RFC 6295 A.4, Figure A.4.1).
///
/// With Z = 1 and U = 1 or W = 1 the logs use the 2-octet header without
/// PNUM-MSB and Q (RFC 6295 A.4.2).
final class MidiRtpChapterM {
  /// Creates a chapter.
  ///
  /// - [s] the S bit.
  /// - [pending] the PENDING field with its Q bit (P = 1): the most recent
  ///   C-active transaction command is the RPN (`nrpn` false) or NRPN MSB
  ///   [pending] sets.
  /// - [e] the E bit: an initiated transaction is in progress.
  /// - [u] the U bit: all logs code RPN parameters.
  /// - [w] the W bit: all logs code NRPN parameters.
  /// - [z] the Z bit: all logs code parameter numbers 0 to 127.
  /// - [logs] the parameter logs, oldest transaction first.
  MidiRtpChapterM({
    this.s = true,
    this.pending,
    this.e = false,
    this.u = false,
    this.w = false,
    this.z = false,
    Iterable<MidiRtpParameterLog> logs = const [],
  }) : logs = List.unmodifiable(logs) {
    assert(pending == null || (pending!.value >= 0 && pending!.value <= 127));
    assert(!u || this.logs.every((log) => !log.nrpn));
    assert(!w || this.logs.every((log) => log.nrpn));
    assert(!z || this.logs.every((log) => log.number <= 0x7F));
  }

  // ...........................................................................
  /// Reads a chapter at the position of [reader]; the LENGTH field bounds
  /// the log list.
  factory MidiRtpChapterM.read(MidiRtpByteReader reader) {
    final header = reader.readUint16();
    final length = header & 0x03FF;
    if (length < 2) {
      throw FormatException('Chapter M LENGTH $length is too small');
    }
    final body = reader.take(length - 2);
    final p = (header & 0x4000) != 0;
    final u = (header & 0x1000) != 0;
    final w = (header & 0x0800) != 0;
    final z = (header & 0x0400) != 0;
    ({int value, bool nrpn})? pending;
    if (p) {
      final octet = body.readUint8();
      pending = (value: octet & 0x7F, nrpn: octet >= 0x80);
    }
    final logs = <MidiRtpParameterLog>[];
    while (!body.isAtEnd) {
      logs.add(
        MidiRtpParameterLog.read(body, shortHeader: z && (u || w), nrpn: w),
      );
    }
    return MidiRtpChapterM(
      s: (header & 0x8000) != 0,
      pending: pending,
      e: (header & 0x2000) != 0,
      u: u,
      w: w,
      z: z,
      logs: logs,
    );
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  ///
  /// Throws an [ArgumentError] when the chapter exceeds 1023 octets.
  Uint8List toBytes() {
    final body = <int>[
      if (pending != null) (pending!.nrpn ? 0x80 : 0) | pending!.value,
      for (final log in logs) ...log.toBytes(shortHeader: shortHeaders),
    ];
    final length = body.length + 2;
    if (length > 0x03FF) {
      throw ArgumentError.value(length, 'length', 'Chapter M is too long');
    }
    final header =
        (s ? 0x8000 : 0) |
        (pending != null ? 0x4000 : 0) |
        (e ? 0x2000 : 0) |
        (u ? 0x1000 : 0) |
        (w ? 0x0800 : 0) |
        (z ? 0x0400 : 0) |
        length;
    return Uint8List.fromList([header >> 8, header & 0xFF, ...body]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterM copyWith({
    bool? s,
    ({int value, bool nrpn})? pending,
    bool? e,
    bool? u,
    bool? w,
    bool? z,
    Iterable<MidiRtpParameterLog>? logs,
  }) => MidiRtpChapterM(
    s: s ?? this.s,
    pending: pending ?? this.pending,
    e: e ?? this.e,
    u: u ?? this.u,
    w: w ?? this.w,
    z: z ?? this.z,
    logs: logs ?? this.logs,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The PENDING field and its Q bit, present when the P bit is set.
  final ({int value, bool nrpn})? pending;

  /// The E bit: an initiated transaction is in progress.
  final bool e;

  /// The U bit: all logs code RPN parameters.
  final bool u;

  /// The W bit: all logs code NRPN parameters.
  final bool w;

  /// The Z bit: all logs code parameter numbers 0 to 127.
  final bool z;

  /// The parameter logs, oldest transaction first; cannot be modified.
  final List<MidiRtpParameterLog> logs;

  /// Whether the logs use the 2-octet header.
  bool get shortHeaders => z && (u || w);

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterM &&
      other.s == s &&
      other.pending == pending &&
      other.e == e &&
      other.u == u &&
      other.w == w &&
      other.z == z &&
      MidiRtpEquality.lists(other.logs, logs);

  @override
  int get hashCode =>
      Object.hash(s, pending, e, u, w, z, MidiRtpEquality.hash(logs));

  @override
  String toString() =>
      'MidiRtpChapterM(s: $s, pending: $pending, e: $e, u: $u, w: $w, '
      'z: $z, logs: $logs)';
}
