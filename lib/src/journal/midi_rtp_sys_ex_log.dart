// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../payload/midi_rtp_delta_time.dart';
import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_sys_ex_status.dart';

// #############################################################################
/// A Chapter X command log: the recovery data of one finished or unfinished
/// System Exclusive command (RFC 6295 B.5.1, Figure B.5.1).
final class MidiRtpSysExLog {
  /// Creates a log.
  ///
  /// - [s] the S bit as coded; for the first log of a chapter it is the S
  ///   bit of Chapter X (see `MidiRtpChapterX.isSafe`).
  /// - [tcount] the TCOUNT field (T): the commands of the log's SysEx type
  ///   in the session history, modulo 256.
  /// - [count] the COUNT field (C): all SysEx commands in the session
  ///   history, modulo 256.
  /// - [first] the FIRST field (F): the number of data octets of the
  ///   command before the first octet in [data].
  /// - [data] the DATA field (D): data octets of the command.
  /// - [l] the L bit: the log uses the list tool, not the recency tool.
  /// - [status] the STA field.
  MidiRtpSysExLog({
    this.s = true,
    this.tcount,
    this.count,
    this.first,
    Iterable<int>? data,
    this.l = false,
    required this.status,
  }) : data = data == null
           ? null
           : Uint8List.fromList(data.toList()).asUnmodifiableView() {
    assert(tcount == null || (tcount! >= 0 && tcount! <= 0xFF));
    assert(count == null || (count! >= 0 && count! <= 0xFF));
    assert(first == null || (first! >= 0 && first! <= MidiRtpDeltaTime.max));
    assert(this.data == null || this.data!.isNotEmpty);
    assert(this.data == null || this.data!.every((b) => b <= 0x7F));
  }

  // ...........................................................................
  /// Reads a log at the position of [reader].
  factory MidiRtpSysExLog.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    final tcount = (header & 0x40) != 0 ? reader.readUint8() : null;
    final count = (header & 0x20) != 0 ? reader.readUint8() : null;
    final first = (header & 0x10) != 0 ? MidiRtpDeltaTime.read(reader) : null;
    List<int>? data;
    if ((header & 0x08) != 0) {
      data = [];
      int octet;
      do {
        octet = reader.readUint8();
        data.add(octet & 0x7F);
      } while (octet < 0x80);
    }
    return MidiRtpSysExLog(
      s: header >= 0x80,
      tcount: tcount,
      count: count,
      first: first,
      data: data,
      l: (header & 0x04) != 0,
      status: MidiRtpSysExStatus.values[header & 0x03],
    );
  }

  // ...........................................................................
  /// Returns the encoded log.
  Uint8List toBytes() => Uint8List.fromList([
    (s ? 0x80 : 0) |
        (tcount != null ? 0x40 : 0) |
        (count != null ? 0x20 : 0) |
        (first != null ? 0x10 : 0) |
        (data != null ? 0x08 : 0) |
        (l ? 0x04 : 0) |
        status.index,
    ?tcount,
    ?count,
    if (first != null) ...MidiRtpDeltaTime.encode(first!),
    if (data != null)
      for (var i = 0; i < data!.length; i++)
        data![i] | (i == data!.length - 1 ? 0x80 : 0),
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpSysExLog copyWith({
    bool? s,
    int? tcount,
    int? count,
    int? first,
    Iterable<int>? data,
    bool? l,
    MidiRtpSysExStatus? status,
  }) => MidiRtpSysExLog(
    s: s ?? this.s,
    tcount: tcount ?? this.tcount,
    count: count ?? this.count,
    first: first ?? this.first,
    data: data ?? this.data,
    l: l ?? this.l,
    status: status ?? this.status,
  );

  // ...........................................................................
  /// The S bit as coded.
  final bool s;

  /// The TCOUNT field.
  final int? tcount;

  /// The COUNT field.
  final int? count;

  /// The FIRST field.
  final int? first;

  /// The DATA field; cannot be modified.
  final Uint8List? data;

  /// The L bit: the list tool codes the log.
  final bool l;

  /// The STA field.
  final MidiRtpSysExStatus status;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpSysExLog &&
      other.s == s &&
      other.tcount == tcount &&
      other.count == count &&
      other.first == first &&
      MidiRtpEquality.lists(other.data, data) &&
      other.l == l &&
      other.status == status;

  @override
  int get hashCode => Object.hash(
    s,
    tcount,
    count,
    first,
    MidiRtpEquality.hash(data),
    l,
    status,
  );

  @override
  String toString() =>
      'MidiRtpSysExLog(s: $s, tcount: $tcount, count: $count, '
      'first: $first, data: ${MidiRtpEquality.hex(data)}, l: $l, '
      'status: ${status.name})';
}
