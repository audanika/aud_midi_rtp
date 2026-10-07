// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterV', () {
    const chapter = MidiRtpChapterV(s: false, count: 0x7F);
    // RFC 6295 Figure B.2.1: |S|COUNT|.

    test('codes the 8-bit chapter', () {
      expect(chapter.toBytes(), equals([0x7F]));
      expect(const MidiRtpChapterV(count: 1).toBytes(), equals([0x81]));
      expect(MidiRtpChapterV.length, 1);
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterV.read(MidiRtpByteReader([0x7F])), chapter);
    });

    test('copyWith replaces the given fields', () {
      expect(chapter.copyWith(), chapter);
      expect(
        chapter.copyWith(s: true, count: 1),
        const MidiRtpChapterV(count: 1),
      );
    });

    test('compares by value', () {
      expect(chapter, const MidiRtpChapterV(s: false, count: 0x7F));
      expect(
        chapter.hashCode,
        const MidiRtpChapterV(s: false, count: 0x7F).hashCode,
      );
      expect(chapter == chapter.copyWith(s: true), isFalse);
      expect(chapter == chapter.copyWith(count: 0), isFalse);
      expect(chapter.toString(), 'MidiRtpChapterV(s: false, count: 127)');
    });
  });
}
