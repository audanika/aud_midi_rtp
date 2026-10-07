// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterW', () {
    const chapter = MidiRtpChapterW(value: 0x1234);
    // RFC 6295 Figure A.5.1: |S|FIRST|R|SECOND|, FIRST the low seven bits.
    const bytes = [0xB4, 0x24];

    test('codes the 16-bit chapter', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(
        const MidiRtpChapterW(s: false, value: 0x2000).toBytes(),
        equals([0x00, 0x40]),
      );
      expect(MidiRtpChapterW.length, 2);
    });

    test('decodes the chapter and ignores the R bit', () {
      expect(MidiRtpChapterW.read(MidiRtpByteReader(bytes)), chapter);
      expect(MidiRtpChapterW.read(MidiRtpByteReader([0xB4, 0xA4])), chapter);
    });

    test('copyWith replaces the given fields', () {
      expect(chapter.copyWith(), chapter);
      expect(
        chapter.copyWith(s: false, value: 1),
        const MidiRtpChapterW(s: false, value: 1),
      );
    });

    test('compares by value', () {
      expect(chapter, const MidiRtpChapterW(value: 0x1234));
      expect(chapter.hashCode, const MidiRtpChapterW(value: 0x1234).hashCode);
      expect(chapter == chapter.copyWith(s: false), isFalse);
      expect(chapter == chapter.copyWith(value: 0), isFalse);
      expect(chapter.toString(), 'MidiRtpChapterW(s: true, value: 4660)');
    });
  });
}
