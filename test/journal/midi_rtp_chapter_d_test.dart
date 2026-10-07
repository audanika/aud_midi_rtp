// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterD', () {
    final f4 = MidiRtpUndefinedCommonLog(dsz: 0, count: 1);
    final f5 = MidiRtpUndefinedCommonLog(dsz: 1, value: [2]);
    final f9 = MidiRtpUndefinedRealTimeLog(count: 3);
    final fd = MidiRtpUndefinedRealTimeLog(count: 4);
    final chapter = MidiRtpChapterD(
      reset: (s: false, value: 3),
      tuneRequest: (s: true, value: 1),
      songSelect: (s: true, value: 7),
      f4: f4,
      f5: f5,
      f9: f9,
      fd: fd,
    );
    // RFC 6295 Figures B.1.1 to B.1.5: |S|B|G|H|J|K|Y|Z| and the logs in
    // that order.
    const bytes = [
      0xFF, 0x03, 0x81, 0x87, //
      0xC0, 0x03, 0x01, //
      0xA4, 0x03, 0x82, //
      0xC2, 0x03, //
      0xC2, 0x04, //
    ];

    test('codes the header and every log', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(
        const MidiRtpChapterD(
          s: false,
          songSelect: (s: true, value: 1),
        ).toBytes(),
        equals([0x10, 0x81]),
      );
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterD.read(MidiRtpByteReader(bytes)), chapter);
    });

    test('copyWith replaces the given fields', () {
      const empty = MidiRtpChapterD();
      expect(chapter.copyWith(), chapter);
      expect(
        empty.copyWith(
          reset: chapter.reset,
          tuneRequest: chapter.tuneRequest,
          songSelect: chapter.songSelect,
          f4: f4,
          f5: f5,
          f9: f9,
          fd: fd,
        ),
        chapter,
      );
      expect(empty.copyWith(s: false).s, isFalse);
    });

    test('compares by value', () {
      final same = MidiRtpChapterD.read(MidiRtpByteReader(bytes));
      expect(chapter, same);
      expect(chapter.hashCode, same.hashCode);
      const empty = MidiRtpChapterD();
      for (final other in [
        chapter.copyWith(s: false),
        empty.copyWith(reset: chapter.reset),
        empty.copyWith(tuneRequest: chapter.tuneRequest),
        empty.copyWith(songSelect: chapter.songSelect),
        empty.copyWith(f4: f4),
        empty.copyWith(f5: f5),
        empty.copyWith(f9: f9),
        empty.copyWith(fd: fd),
      ]) {
        expect(empty == other, isFalse);
      }
      expect(chapter.toString(), startsWith('MidiRtpChapterD(s: true, '));
    });
  });
}
