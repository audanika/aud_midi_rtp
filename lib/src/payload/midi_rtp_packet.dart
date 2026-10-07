// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import 'midi_rtp_header.dart';
import 'midi_rtp_payload.dart';

// #############################################################################
/// An RTP MIDI packet: the RTP header, the MIDI payload and optional
/// padding octets (RFC 6295 2, Figure 1; RFC 3550 5.1).
final class MidiRtpPacket {
  /// Creates a packet; [paddingLength] adds that many padding octets, 0 to
  /// 255, and sets the P bit when it is not 0.
  MidiRtpPacket({
    required this.header,
    required this.payload,
    this.paddingLength = 0,
  }) : assert(paddingLength >= 0 && paddingLength <= 0xFF);

  // ...........................................................................
  /// Decodes a packet from [bytes].
  ///
  /// Throws a [FormatException] when the packet is malformed.
  factory MidiRtpPacket.decode(List<int> bytes) {
    final reader = MidiRtpByteReader(bytes);
    final header = MidiRtpHeader.read(reader);
    var paddingLength = 0;
    if ((bytes[0] & 0x20) != 0) {
      paddingLength = bytes.last;
      if (paddingLength == 0 || paddingLength > reader.remaining) {
        throw FormatException('Illegal padding count $paddingLength');
      }
    }
    return MidiRtpPacket(
      header: header,
      payload: MidiRtpPayload.read(
        reader.take(reader.remaining - paddingLength),
      ),
      paddingLength: paddingLength,
    );
  }

  // ...........................................................................
  /// Returns the encoded packet.
  Uint8List toBytes() => Uint8List.fromList([
    ...header.toBytes(padding: paddingLength > 0),
    ...payload.toBytes(),
    if (paddingLength > 0) ...[
      for (var i = 1; i < paddingLength; i++) 0,
      paddingLength,
    ],
  ]);

  /// Returns a copy with the given fields replaced.
  MidiRtpPacket copyWith({
    MidiRtpHeader? header,
    MidiRtpPayload? payload,
    int? paddingLength,
  }) => MidiRtpPacket(
    header: header ?? this.header,
    payload: payload ?? this.payload,
    paddingLength: paddingLength ?? this.paddingLength,
  );

  // ...........................................................................
  /// The RTP header.
  final MidiRtpHeader header;

  /// The MIDI payload.
  final MidiRtpPayload payload;

  /// The number of padding octets at the end of the packet.
  final int paddingLength;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpPacket &&
      other.header == header &&
      other.payload == payload &&
      other.paddingLength == paddingLength;

  @override
  int get hashCode => Object.hash(header, payload, paddingLength);

  @override
  String toString() =>
      'MidiRtpPacket(header: $header, payload: $payload, '
      'paddingLength: $paddingLength)';
}
