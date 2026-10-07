// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterQ', () {
    const chapter = MidiRtpChapterQ(n: true, position: 0x51234, time: 0x010203);
    // RFC 6295 Figures B.3.1 and B.3.2: |S|N|D|C|T|TOP|, CLOCK, TIMETOOLS.
    const bytes = [0xDD, 0x12, 0x34, 0x01, 0x02, 0x03];

    test('codes header, CLOCK and TIMETOOLS', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(
        const MidiRtpChapterQ(s: false, d: true).toBytes(),
        equals([0x20]),
      );
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterQ.read(MidiRtpByteReader(bytes)), chapter);
      expect(
        MidiRtpChapterQ.read(MidiRtpByteReader([0x20])),
        const MidiRtpChapterQ(s: false, d: true),
      );
    });

    test('copyWith replaces the given fields', () {
      const empty = MidiRtpChapterQ();
      expect(chapter.copyWith(), chapter);
      expect(
        empty.copyWith(
          s: true,
          n: true,
          d: false,
          position: 0x51234,
          time: 0x010203,
        ),
        chapter,
      );
    });

    test('compares by value', () {
      final same = MidiRtpChapterQ.read(MidiRtpByteReader(bytes));
      expect(chapter, same);
      expect(chapter.hashCode, same.hashCode);
      for (final other in [
        chapter.copyWith(s: false),
        chapter.copyWith(n: false),
        chapter.copyWith(d: true),
        chapter.copyWith(position: 1),
        chapter.copyWith(time: 1),
      ]) {
        expect(chapter == other, isFalse);
      }
      expect(
        chapter.toString(),
        'MidiRtpChapterQ(s: true, n: true, d: false, position: 332340, '
        'time: 66051)',
      );
    });
  });
}
