// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterT', () {
    const chapter = MidiRtpChapterT(pressure: 0x45);
    // RFC 6295 Figure A.8.1: |S|PRESSURE|.

    test('codes the 8-bit chapter', () {
      expect(chapter.toBytes(), equals([0xC5]));
      expect(
        const MidiRtpChapterT(s: false, pressure: 1).toBytes(),
        equals([0x01]),
      );
      expect(MidiRtpChapterT.length, 1);
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterT.read(MidiRtpByteReader([0xC5])), chapter);
    });

    test('copyWith replaces the given fields', () {
      expect(chapter.copyWith(), chapter);
      expect(
        chapter.copyWith(s: false, pressure: 2),
        const MidiRtpChapterT(s: false, pressure: 2),
      );
    });

    test('compares by value', () {
      expect(chapter, const MidiRtpChapterT(pressure: 0x45));
      expect(chapter.hashCode, const MidiRtpChapterT(pressure: 0x45).hashCode);
      expect(chapter == chapter.copyWith(s: false), isFalse);
      expect(chapter == chapter.copyWith(pressure: 0), isFalse);
      expect(chapter.toString(), 'MidiRtpChapterT(s: true, pressure: 69)');
    });
  });
}
