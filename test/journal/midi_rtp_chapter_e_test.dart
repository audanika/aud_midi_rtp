// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterE', () {
    final chapter = MidiRtpChapterE(
      logs: [
        const MidiRtpNoteExtraLog(note: 60, v: false, value: 2),
        const MidiRtpNoteExtraLog(note: 60, v: true, value: 90),
      ],
    );
    // RFC 6295 Figure A.7.1: |S|LEN| with LEN = logs - 1, then the logs.
    const bytes = [0x81, 0xBC, 0x02, 0xBC, 0xDA];

    test('codes header and logs', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(chapter.length, 5);
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterE.read(MidiRtpByteReader(bytes)), chapter);
    });

    test('rejects an empty log list', () {
      expect(
        () => MidiRtpChapterE(logs: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith replaces the given fields', () {
      expect(chapter.copyWith(), chapter);
      final changed = chapter.copyWith(s: false, logs: chapter.logs.skip(1));
      expect(changed.s, isFalse);
      expect(changed.logs, equals(chapter.logs.skip(1)));
    });

    test('compares by value', () {
      final same = MidiRtpChapterE.read(MidiRtpByteReader(bytes));
      expect(chapter, same);
      expect(chapter.hashCode, same.hashCode);
      expect(chapter == chapter.copyWith(s: false), isFalse);
      expect(chapter == chapter.copyWith(logs: chapter.logs.skip(1)), isFalse);
      expect(
        chapter.toString(),
        startsWith('MidiRtpChapterE(s: true, logs: ['),
      );
    });
  });
}
