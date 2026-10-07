// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';

// #############################################################################
/// A parameter log of Chapter M: the recovery data of one RPN or NRPN
/// parameter (RFC 6295 A.4.2, Figures A.4.2 to A.4.7).
///
/// The value tool ([v]) codes the most recent Data Entry MSB and LSB
/// (controllers 6 and 38) and the Data Increment/Decrement count (96, 97)
/// since then; the count tool ([t]) codes the number of transactions. X
/// bits flag fields that precede the most recent Reset All Controllers.
final class MidiRtpParameterLog {
  /// Creates a log.
  ///
  /// - [s] the S bit: false when the previous packet holds a command of the
  ///   log.
  /// - [nrpn] the Q bit: an NRPN instead of an RPN parameter.
  /// - [number] the 14-bit parameter number (PNUM-MSB, PNUM-LSB).
  /// - [t] the T bit: the sender uses the count tool for the parameter.
  /// - [v] the V bit: the sender uses the value tool for the parameter.
  /// - [entryMsb] the ENTRY-MSB field (J), with its X bit.
  /// - [entryLsb] the ENTRY-LSB field (K), with its X bit.
  /// - [aButton] the signed A-BUTTON count (L), with its X bit.
  /// - [cButton] the signed C-BUTTON count (M).
  /// - [count] the COUNT field (N), with its X bit.
  const MidiRtpParameterLog({
    this.s = true,
    this.nrpn = false,
    required this.number,
    this.t = false,
    this.v = true,
    this.entryMsb,
    this.entryLsb,
    this.aButton,
    this.cButton,
    this.count,
  }) : assert(number >= 0 && number <= 0x3FFF);

  // ...........................................................................
  /// Reads a log at the position of [reader].
  ///
  /// A short header (Chapter M with Z = 1 and U = 1 or W = 1) has no Q and
  /// PNUM-MSB fields; [nrpn] then tells the parameter type and the MSB is 0.
  factory MidiRtpParameterLog.read(
    MidiRtpByteReader reader, {
    bool shortHeader = false,
    bool nrpn = false,
  }) {
    final first = reader.readUint8();
    var msb = 0;
    if (!shortHeader) {
      final second = reader.readUint8();
      nrpn = second >= 0x80;
      msb = second & 0x7F;
    }
    final toc = reader.readUint8();
    ({int value, bool x})? field(int mask) {
      if ((toc & mask) == 0) return null;
      final octet = reader.readUint8();
      return (value: octet & 0x7F, x: octet >= 0x80);
    }

    int signed(int word) =>
        (word & 0x8000) != 0 ? -(word & 0x3FFF) : word & 0x3FFF;

    final entryMsb = field(0x80);
    final entryLsb = field(0x40);
    final aWord = (toc & 0x20) != 0 ? reader.readUint16() : null;
    final cWord = (toc & 0x10) != 0 ? reader.readUint16() : null;
    return MidiRtpParameterLog(
      s: first >= 0x80,
      nrpn: nrpn,
      number: msb << 7 | (first & 0x7F),
      t: (toc & 0x04) != 0,
      v: (toc & 0x02) != 0,
      entryMsb: entryMsb,
      entryLsb: entryLsb,
      aButton: aWord == null
          ? null
          : (count: signed(aWord), x: (aWord & 0x4000) != 0),
      cButton: cWord == null ? null : signed(cWord),
      count: field(0x08),
    );
  }

  // ...........................................................................
  /// Returns the encoded log; [shortHeader] leaves out Q and PNUM-MSB.
  Uint8List toBytes({bool shortHeader = false}) {
    int field(({int value, bool x}) f) => (f.x ? 0x80 : 0) | f.value;
    List<int> word(int count, bool x) {
      final magnitude = count.abs().clamp(0, 0x3FFF);
      final value = (count < 0 ? 0x8000 : 0) | (x ? 0x4000 : 0) | magnitude;
      return [value >> 8, value & 0xFF];
    }

    return Uint8List.fromList([
      (s ? 0x80 : 0) | (number & 0x7F),
      if (!shortHeader) (nrpn ? 0x80 : 0) | number >> 7,
      (entryMsb != null ? 0x80 : 0) |
          (entryLsb != null ? 0x40 : 0) |
          (aButton != null ? 0x20 : 0) |
          (cButton != null ? 0x10 : 0) |
          (count != null ? 0x08 : 0) |
          (t ? 0x04 : 0) |
          (v ? 0x02 : 0),
      if (entryMsb != null) field(entryMsb!),
      if (entryLsb != null) field(entryLsb!),
      if (aButton != null) ...word(aButton!.count, aButton!.x),
      if (cButton != null) ...word(cButton!, false),
      if (count != null) field(count!),
    ]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpParameterLog copyWith({
    bool? s,
    bool? nrpn,
    int? number,
    bool? t,
    bool? v,
    ({int value, bool x})? entryMsb,
    ({int value, bool x})? entryLsb,
    ({int count, bool x})? aButton,
    int? cButton,
    ({int value, bool x})? count,
  }) => MidiRtpParameterLog(
    s: s ?? this.s,
    nrpn: nrpn ?? this.nrpn,
    number: number ?? this.number,
    t: t ?? this.t,
    v: v ?? this.v,
    entryMsb: entryMsb ?? this.entryMsb,
    entryLsb: entryLsb ?? this.entryLsb,
    aButton: aButton ?? this.aButton,
    cButton: cButton ?? this.cButton,
    count: count ?? this.count,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The Q bit: the log codes an NRPN parameter.
  final bool nrpn;

  /// The 14-bit parameter number.
  final int number;

  /// The T bit: the sender uses the count tool.
  final bool t;

  /// The V bit: the sender uses the value tool.
  final bool v;

  /// The ENTRY-MSB field: the most recent Data Entry MSB of the parameter.
  final ({int value, bool x})? entryMsb;

  /// The ENTRY-LSB field: the most recent Data Entry LSB of the parameter.
  final ({int value, bool x})? entryLsb;

  /// The A-BUTTON field: the net Data Increment count since the last Data
  /// Entry, from -16383 to 16383.
  final ({int count, bool x})? aButton;

  /// The C-BUTTON field: like [aButton] without the commands before the
  /// most recent Reset All Controllers.
  final int? cButton;

  /// The COUNT field: the number of transactions modulo 128.
  final ({int value, bool x})? count;

  /// The MSB of the parameter number.
  int get msb => number >> 7;

  /// The LSB of the parameter number.
  int get lsb => number & 0x7F;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpParameterLog &&
      other.s == s &&
      other.nrpn == nrpn &&
      other.number == number &&
      other.t == t &&
      other.v == v &&
      other.entryMsb == entryMsb &&
      other.entryLsb == entryLsb &&
      other.aButton == aButton &&
      other.cButton == cButton &&
      other.count == count;

  @override
  int get hashCode => Object.hash(
    s,
    nrpn,
    number,
    t,
    v,
    entryMsb,
    entryLsb,
    aButton,
    cButton,
    count,
  );

  @override
  String toString() =>
      'MidiRtpParameterLog(s: $s, nrpn: $nrpn, number: $number, t: $t, '
      'v: $v, entryMsb: $entryMsb, entryLsb: $entryLsb, '
      'aButton: $aButton, cButton: $cButton, count: $count)';
}
