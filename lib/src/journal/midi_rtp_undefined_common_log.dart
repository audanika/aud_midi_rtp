// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';

// #############################################################################
/// A Chapter D command log of an undefined System Common command, 0xF4 or
/// 0xF5 (RFC 6295 B.1.1, Figure B.1.4).
///
/// The reserved LEGAL field is kept as raw octets so that logs of future
/// senders re-encode unchanged.
final class MidiRtpUndefinedCommonLog {
  /// Creates a log.
  ///
  /// - [s] the S bit.
  /// - [dsz] the data size of the most recent command: 0 to 2 octets, or 3
  ///   for three and more.
  /// - [count] the COUNT field (C): the number of commands modulo 256.
  /// - [value] the VALUE field (V): the data octets of the most recent
  ///   command.
  /// - [legal] the reserved LEGAL field (L) as raw octets.
  MidiRtpUndefinedCommonLog({
    this.s = true,
    required this.dsz,
    this.count,
    Iterable<int>? value,
    Iterable<int>? legal,
  }) : value = value == null
           ? null
           : Uint8List.fromList(value.toList()).asUnmodifiableView(),
       legal = legal == null
           ? null
           : Uint8List.fromList(legal.toList()).asUnmodifiableView() {
    assert(dsz >= 0 && dsz <= 3);
    assert(count == null || (count! >= 0 && count! <= 0xFF));
    assert(this.value == null || this.value!.isNotEmpty);
    assert(this.value == null || this.value!.every((b) => b <= 0x7F));
  }

  // ...........................................................................
  /// Reads a log at the position of [reader]; the LENGTH field bounds it.
  factory MidiRtpUndefinedCommonLog.read(MidiRtpByteReader reader) {
    final header = reader.readUint16();
    final length = header & 0x03FF;
    if (length < 2) {
      throw FormatException('Command log LENGTH $length is too small');
    }
    final body = reader.take(length - 2);
    final count = (header & 0x4000) != 0 ? body.readUint8() : null;
    List<int>? value;
    if ((header & 0x2000) != 0) {
      value = [];
      int octet;
      do {
        octet = body.readUint8();
        value.add(octet & 0x7F);
      } while (octet < 0x80);
    }
    return MidiRtpUndefinedCommonLog(
      s: (header & 0x8000) != 0,
      dsz: (header >> 10) & 0x03,
      count: count,
      value: value,
      legal: (header & 0x1000) != 0 ? body.readBytes(body.remaining) : null,
    );
  }

  // ...........................................................................
  /// Returns the encoded log.
  Uint8List toBytes() {
    final body = <int>[
      ?count,
      if (value != null)
        for (var i = 0; i < value!.length; i++)
          value![i] | (i == value!.length - 1 ? 0x80 : 0),
      ...?legal,
    ];
    final length = body.length + 2;
    final header =
        (s ? 0x8000 : 0) |
        (count != null ? 0x4000 : 0) |
        (value != null ? 0x2000 : 0) |
        (legal != null ? 0x1000 : 0) |
        dsz << 10 |
        length;
    return Uint8List.fromList([header >> 8, header & 0xFF, ...body]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpUndefinedCommonLog copyWith({
    bool? s,
    int? dsz,
    int? count,
    Iterable<int>? value,
    Iterable<int>? legal,
  }) => MidiRtpUndefinedCommonLog(
    s: s ?? this.s,
    dsz: dsz ?? this.dsz,
    count: count ?? this.count,
    value: value ?? this.value,
    legal: legal ?? this.legal,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The DSZ field: the data size class of the most recent command.
  final int dsz;

  /// The COUNT field.
  final int? count;

  /// The VALUE field without the length marker bit; cannot be modified.
  final Uint8List? value;

  /// The reserved LEGAL field; cannot be modified.
  final Uint8List? legal;

  // ...........................................................................
  /// Returns the DSZ value of a command with [dataLength] data octets.
  static int dszOf(int dataLength) => dataLength < 3 ? dataLength : 3;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpUndefinedCommonLog &&
      other.s == s &&
      other.dsz == dsz &&
      other.count == count &&
      MidiRtpEquality.lists(other.value, value) &&
      MidiRtpEquality.lists(other.legal, legal);

  @override
  int get hashCode => Object.hash(
    s,
    dsz,
    count,
    MidiRtpEquality.hash(value),
    MidiRtpEquality.hash(legal),
  );

  @override
  String toString() =>
      'MidiRtpUndefinedCommonLog(s: $s, dsz: $dsz, count: $count, '
      'value: ${MidiRtpEquality.hex(value)}, '
      'legal: ${MidiRtpEquality.hex(legal)})';
}
