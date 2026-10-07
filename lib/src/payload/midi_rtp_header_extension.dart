// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import '../support/midi_rtp_equality.dart';

// #############################################################################
/// The header extension of an RTP packet (RFC 3550 5.3.1): a 16-bit field
/// defined by the profile, a 16-bit length in 32-bit words and the
/// extension data.
///
/// RTP MIDI does not use the extension (RFC 6295 2.1); receivers keep it so
/// that packets of other implementations decode and re-encode unchanged.
final class MidiRtpHeaderExtension {
  /// Creates an extension with the [profile] field and a copy of [data],
  /// whose length must be a multiple of four.
  MidiRtpHeaderExtension({required this.profile, Iterable<int> data = const []})
    : data = Uint8List.fromList(data.toList()).asUnmodifiableView() {
    assert(profile >= 0 && profile <= 0xFFFF);
    assert(this.data.length % 4 == 0 && this.data.length <= 0xFFFF * 4);
  }

  // ...........................................................................
  /// Reads an extension at the position of [reader].
  factory MidiRtpHeaderExtension.read(MidiRtpByteReader reader) {
    final profile = reader.readUint16();
    final words = reader.readUint16();
    return MidiRtpHeaderExtension(
      profile: profile,
      data: reader.readBytes(words * 4),
    );
  }

  // ...........................................................................
  /// Returns the encoded extension.
  Uint8List toBytes() {
    final words = data.length ~/ 4;
    return Uint8List.fromList([
      profile >> 8,
      profile & 0xFF,
      words >> 8,
      words & 0xFF,
      ...data,
    ]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpHeaderExtension copyWith({int? profile, Iterable<int>? data}) =>
      MidiRtpHeaderExtension(
        profile: profile ?? this.profile,
        data: data ?? this.data,
      );

  // ...........................................................................
  /// The 16-bit field whose meaning the profile defines.
  final int profile;

  /// The extension data; cannot be modified.
  final Uint8List data;

  /// The number of encoded bytes.
  int get length => 4 + data.length;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpHeaderExtension &&
      other.profile == profile &&
      MidiRtpEquality.lists(other.data, data);

  @override
  int get hashCode => Object.hash(profile, MidiRtpEquality.hash(data));

  @override
  String toString() =>
      'MidiRtpHeaderExtension(profile: $profile, '
      'data: ${MidiRtpEquality.hex(data)})';
}
