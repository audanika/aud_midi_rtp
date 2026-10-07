// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import '../support/midi_rtp_byte_reader.dart';
import 'midi_rtp_undefined_common_log.dart';
import 'midi_rtp_undefined_real_time_log.dart';

// #############################################################################
/// System Chapter D: the simple system commands Reset, Tune Request, Song
/// Select and the undefined commands 0xF4, 0xF5, 0xF9 and 0xFD (RFC 6295
/// B.1, Figures B.1.1 to B.1.5).
///
/// Each one-octet log carries its own S bit and a 7-bit value: the
/// reference count of Reset and Tune Request commands modulo 128, or the
/// song number of the most recent Song Select.
final class MidiRtpChapterD {
  /// Creates a chapter.
  ///
  /// - [s] the S bit of the chapter.
  /// - [reset] the Reset log (B): the System Reset count.
  /// - [tuneRequest] the Tune Request log (G): the Tune Request count.
  /// - [songSelect] the Song Select log (H): the song number.
  /// - [f4], [f5] the logs of the undefined System Common commands (J, K).
  /// - [f9], [fd] the logs of the undefined System Real-Time commands (Y,
  ///   Z).
  const MidiRtpChapterD({
    this.s = true,
    this.reset,
    this.tuneRequest,
    this.songSelect,
    this.f4,
    this.f5,
    this.f9,
    this.fd,
  });

  // ...........................................................................
  /// Reads a chapter at the position of [reader].
  factory MidiRtpChapterD.read(MidiRtpByteReader reader) {
    final header = reader.readUint8();
    ({bool s, int value})? simple(int mask) {
      if ((header & mask) == 0) return null;
      final octet = reader.readUint8();
      return (s: octet >= 0x80, value: octet & 0x7F);
    }

    final reset = simple(0x40);
    final tuneRequest = simple(0x20);
    final songSelect = simple(0x10);
    final f4 = (header & 0x08) != 0
        ? MidiRtpUndefinedCommonLog.read(reader)
        : null;
    final f5 = (header & 0x04) != 0
        ? MidiRtpUndefinedCommonLog.read(reader)
        : null;
    final f9 = (header & 0x02) != 0
        ? MidiRtpUndefinedRealTimeLog.read(reader)
        : null;
    final fd = (header & 0x01) != 0
        ? MidiRtpUndefinedRealTimeLog.read(reader)
        : null;
    return MidiRtpChapterD(
      s: header >= 0x80,
      reset: reset,
      tuneRequest: tuneRequest,
      songSelect: songSelect,
      f4: f4,
      f5: f5,
      f9: f9,
      fd: fd,
    );
  }

  // ...........................................................................
  /// Returns the encoded chapter.
  Uint8List toBytes() {
    int simple(({bool s, int value}) log) => (log.s ? 0x80 : 0) | log.value;
    return Uint8List.fromList([
      (s ? 0x80 : 0) |
          (reset != null ? 0x40 : 0) |
          (tuneRequest != null ? 0x20 : 0) |
          (songSelect != null ? 0x10 : 0) |
          (f4 != null ? 0x08 : 0) |
          (f5 != null ? 0x04 : 0) |
          (f9 != null ? 0x02 : 0) |
          (fd != null ? 0x01 : 0),
      if (reset != null) simple(reset!),
      if (tuneRequest != null) simple(tuneRequest!),
      if (songSelect != null) simple(songSelect!),
      ...?f4?.toBytes(),
      ...?f5?.toBytes(),
      ...?f9?.toBytes(),
      ...?fd?.toBytes(),
    ]);
  }

  /// Returns a copy with the given fields replaced.
  MidiRtpChapterD copyWith({
    bool? s,
    ({bool s, int value})? reset,
    ({bool s, int value})? tuneRequest,
    ({bool s, int value})? songSelect,
    MidiRtpUndefinedCommonLog? f4,
    MidiRtpUndefinedCommonLog? f5,
    MidiRtpUndefinedRealTimeLog? f9,
    MidiRtpUndefinedRealTimeLog? fd,
  }) => MidiRtpChapterD(
    s: s ?? this.s,
    reset: reset ?? this.reset,
    tuneRequest: tuneRequest ?? this.tuneRequest,
    songSelect: songSelect ?? this.songSelect,
    f4: f4 ?? this.f4,
    f5: f5 ?? this.f5,
    f9: f9 ?? this.f9,
    fd: fd ?? this.fd,
  );

  // ...........................................................................
  /// The S bit.
  final bool s;

  /// The Reset log: S bit and System Reset count modulo 128.
  final ({bool s, int value})? reset;

  /// The Tune Request log: S bit and Tune Request count modulo 128.
  final ({bool s, int value})? tuneRequest;

  /// The Song Select log: S bit and song number.
  final ({bool s, int value})? songSelect;

  /// The log of the undefined System Common command 0xF4.
  final MidiRtpUndefinedCommonLog? f4;

  /// The log of the undefined System Common command 0xF5.
  final MidiRtpUndefinedCommonLog? f5;

  /// The log of the undefined System Real-Time command 0xF9.
  final MidiRtpUndefinedRealTimeLog? f9;

  /// The log of the undefined System Real-Time command 0xFD.
  final MidiRtpUndefinedRealTimeLog? fd;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpChapterD &&
      other.s == s &&
      other.reset == reset &&
      other.tuneRequest == tuneRequest &&
      other.songSelect == songSelect &&
      other.f4 == f4 &&
      other.f5 == f5 &&
      other.f9 == f9 &&
      other.fd == fd;

  @override
  int get hashCode =>
      Object.hash(s, reset, tuneRequest, songSelect, f4, f5, f9, fd);

  @override
  String toString() =>
      'MidiRtpChapterD(s: $s, reset: $reset, tuneRequest: $tuneRequest, '
      'songSelect: $songSelect, f4: $f4, f5: $f5, f9: $f9, fd: $fd)';
}
