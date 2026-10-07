// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';
import 'midi_rtp_header_extension.dart';

// #############################################################################
/// The RTP header of an RTP MIDI packet (RFC 3550 5.1, RFC 6295 2.1): V=2,
/// P, X, CC, M, PT, sequence number, timestamp, SSRC and the CSRC list.
///
/// The padding bit P belongs to the packet, which knows the padding octets
/// at its end (see `MidiRtpPacket`); the header only writes it.
final class MidiRtpHeader {
  /// Creates a header.
  ///
  /// - [marker] the M bit; native RTP MIDI streams set it when the MIDI
  ///   list is not empty (RFC 6295 2.1).
  /// - [payloadType] the 7-bit payload type.
  /// - [sequenceNumber] the 16-bit sequence number.
  /// - [timestamp] the 32-bit RTP timestamp in units of the clock rate.
  /// - [ssrc] the 32-bit synchronization source.
  /// - [csrcs] up to 15 contributing sources.
  /// - [extension] the optional header extension (X bit).
  MidiRtpHeader({
    this.marker = false,
    required this.payloadType,
    required this.sequenceNumber,
    required this.timestamp,
    required this.ssrc,
    Iterable<int> csrcs = const [],
    this.extension,
  }) : csrcs = List.unmodifiable(csrcs) {
    assert(payloadType >= 0 && payloadType <= 0x7F);
    assert(sequenceNumber >= 0 && sequenceNumber <= 0xFFFF);
    assert(timestamp >= 0 && timestamp <= 0xFFFFFFFF);
    assert(ssrc >= 0 && ssrc <= 0xFFFFFFFF);
    assert(this.csrcs.length <= 15);
  }

  // ...........................................................................
  /// Reads a header at the position of [reader].
  ///
  /// Throws a [FormatException] when the version is not 2 or the data ends
  /// early. The padding bit is left to the caller.
  factory MidiRtpHeader.read(MidiRtpByteReader reader) {
    final first = reader.readUint8();
    if (first >> 6 != version) {
      throw FormatException('Unsupported RTP version ${first >> 6}');
    }
    final second = reader.readUint8();
    final sequenceNumber = reader.readUint16();
    final timestamp = reader.readUint32();
    final ssrc = reader.readUint32();
    final csrcs = [
      for (var i = 0; i < (first & 0x0F); i++) reader.readUint32(),
    ];
    final extension = (first & 0x10) != 0
        ? MidiRtpHeaderExtension.read(reader)
        : null;
    return MidiRtpHeader(
      marker: (second & 0x80) != 0,
      payloadType: second & 0x7F,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp,
      ssrc: ssrc,
      csrcs: csrcs,
      extension: extension,
    );
  }

  // ...........................................................................
  /// Returns the encoded header; [padding] sets the P bit.
  Uint8List toBytes({bool padding = false}) {
    final builder = BytesBuilder(copy: false)
      ..addByte(
        version << 6 |
            (padding ? 0x20 : 0) |
            (extension != null ? 0x10 : 0) |
            csrcs.length,
      )
      ..addByte((marker ? 0x80 : 0) | payloadType)
      ..add(_uint(sequenceNumber, 2))
      ..add(_uint(timestamp, 4))
      ..add(_uint(ssrc, 4));
    for (final csrc in csrcs) {
      builder.add(_uint(csrc, 4));
    }
    if (extension != null) builder.add(extension!.toBytes());
    return builder.toBytes();
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpHeader copyWith({
    bool? marker,
    int? payloadType,
    int? sequenceNumber,
    int? timestamp,
    int? ssrc,
    Iterable<int>? csrcs,
    MidiRtpHeaderExtension? extension,
  }) => MidiRtpHeader(
    marker: marker ?? this.marker,
    payloadType: payloadType ?? this.payloadType,
    sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    timestamp: timestamp ?? this.timestamp,
    ssrc: ssrc ?? this.ssrc,
    csrcs: csrcs ?? this.csrcs,
    extension: extension ?? this.extension,
  );

  // ...........................................................................
  /// The M bit.
  final bool marker;

  /// The 7-bit payload type.
  final int payloadType;

  /// The 16-bit sequence number.
  final int sequenceNumber;

  /// The 32-bit RTP timestamp.
  final int timestamp;

  /// The 32-bit synchronization source identifier.
  final int ssrc;

  /// The contributing source identifiers; cannot be modified.
  final List<int> csrcs;

  /// The header extension, present when the X bit is set.
  final MidiRtpHeaderExtension? extension;

  /// The number of encoded bytes.
  int get length => 12 + 4 * csrcs.length + (extension?.length ?? 0);

  // ...........................................................................
  /// The RTP version written into every header.
  static const int version = 2;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpHeader &&
      other.marker == marker &&
      other.payloadType == payloadType &&
      other.sequenceNumber == sequenceNumber &&
      other.timestamp == timestamp &&
      other.ssrc == ssrc &&
      MidiRtpEquality.lists(other.csrcs, csrcs) &&
      other.extension == extension;

  @override
  int get hashCode => Object.hash(
    marker,
    payloadType,
    sequenceNumber,
    timestamp,
    ssrc,
    MidiRtpEquality.hash(csrcs),
    extension,
  );

  @override
  String toString() =>
      'MidiRtpHeader(marker: $marker, payloadType: $payloadType, '
      'sequenceNumber: $sequenceNumber, timestamp: $timestamp, '
      'ssrc: $ssrc, csrcs: $csrcs, extension: $extension)';

  // ...........................................................................
  static List<int> _uint(int value, int bytes) => [
    for (var i = bytes - 1; i >= 0; i--) (value >> (8 * i)) & 0xFF,
  ];
}
