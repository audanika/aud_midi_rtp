// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// Chapter P of a channel journal: the most recent active Program Change
/// and the bank it selected (RFC 6295 A.2, Figure A.2.1).
final class MidiRtpChapterP {
  /// Creates a chapter.
  ///
  /// - [s] the S bit: false when the program change is in the previous
  ///   packet (RFC 6295 A.1).
  /// - [program] the program number.
  /// - [b] the B bit: an active Bank Select MSB (controller 0) preceded the
  ///   program change.
  /// - [bankMsb] the value of that Bank Select MSB.
  /// - [x] the X bit: a Reset All Controllers came between the Bank Select
  ///   MSB and the program change.
  /// - [bankLsb] the most recent Bank Select LSB (controller 32) between
  ///   the Bank Select MSB and the program change, or 0.
  const MidiRtpChapterP({
    this.s = true,
    required this.program,
    this.b = false,
    this.bankMsb = 0,
    this.x = false,
    this.bankLsb = 0,
  }) : assert(program >= 0 && program <= 0x7F),
       assert(bankMsb >= 0 && bankMsb <= 0x7F),
       assert(bankLsb >= 0 && bankLsb <= 0x7F);

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterP.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    final second = reader.readUint8();
    final third = reader.readUint8();
    return MidiRtpChapterP(
      s: first >= 0x80,
      program: first & 0x7F,
      b: second >= 0x80,
      bankMsb: second & 0x7F,
      x: third >= 0x80,
      bankLsb: third & 0x7F,
    );
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) | program,
    (b ? 0x80 : 0) | bankMsb,
    (x ? 0x80 : 0) | bankLsb,
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterP copyWith({
    bool? s,
    int? program,
    bool? b,
    int? bankMsb,
    bool? x,
    int? bankLsb,
  }) => MidiRtpChapterP(
    s: s ?? this.s,
    program: program ?? this.program,
    b: b ?? this.b,
    bankMsb: bankMsb ?? this.bankMsb,
    x: x ?? this.x,
    bankLsb: bankLsb ?? this.bankLsb,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The program number.
  final int program;

  /// The B bit: a Bank Select MSB preceded the program change.
  final bool b;

  /// The Bank Select MSB value.
  final int bankMsb;

  /// The X bit: a Reset All Controllers came between bank and program.
  final bool x;

  /// The Bank Select LSB value.
  final int bankLsb;

  // ...........................................................................
  /// The number of encoded bytes.
  static const int length = 3;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterP &&
      other.s == s &&
      other.program == program &&
      other.b == b &&
      other.bankMsb == bankMsb &&
      other.x == x &&
      other.bankLsb == bankLsb;

  @override
  int get hashCode => Object.hash(s, program, b, bankMsb, x, bankLsb);

  @override
  String toString() =>
      'MidiRtpChapterP(s: $s, program: $program, b: $b, '
      'bankMsb: $bankMsb, x: $x, bankLsb: $bankLsb)';
}
