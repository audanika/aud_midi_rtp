// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterF', () {
    const chapter = MidiRtpChapterF(
      complete: 0x01020304,
      q: true,
      point: 3,
      partial: 0x12340000,
    );
    // RFC 6295 Figure B.4.1: |S|C|P|Q|D|POINT|, COMPLETE, PARTIAL.
    const bytes = [0xF3, 1, 2, 3, 4, 0x12, 0x34, 0, 0];

    test('codes header, COMPLETE and PARTIAL', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(
        const MidiRtpChapterF(s: false, d: true, point: 0).toBytes(),
        equals([0x08]),
      );
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterF.read(MidiRtpByteReader(bytes)), chapter);
      expect(
        MidiRtpChapterF.read(MidiRtpByteReader([0x08])),
        const MidiRtpChapterF(s: false, d: true, point: 0),
      );
    });

    test('copyWith replaces the given fields', () {
      const empty = MidiRtpChapterF();
      expect(chapter.copyWith(), chapter);
      expect(
        empty.copyWith(
          s: true,
          complete: 0x01020304,
          q: true,
          d: false,
          point: 3,
          partial: 0x12340000,
        ),
        chapter,
      );
    });

    test('compares by value', () {
      final same = MidiRtpChapterF.read(MidiRtpByteReader(bytes));
      expect(chapter, same);
      expect(chapter.hashCode, same.hashCode);
      for (final other in [
        chapter.copyWith(s: false),
        chapter.copyWith(complete: 1),
        chapter.copyWith(q: false),
        chapter.copyWith(d: true),
        chapter.copyWith(point: 4),
        chapter.copyWith(partial: 1),
      ]) {
        expect(chapter == other, isFalse);
      }
      expect(
        chapter.toString(),
        'MidiRtpChapterF(s: true, complete: 16909060, q: true, d: false, '
        'point: 3, partial: 305397760)',
      );
    });
  });
}
