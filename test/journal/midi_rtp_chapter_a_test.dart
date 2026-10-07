// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterA', () {
    final chapter = MidiRtpChapterA(
      s: false,
      logs: [
        const MidiRtpPressureLog(note: 60, pressure: 10),
        const MidiRtpPressureLog(s: false, note: 61, x: true, pressure: 11),
      ],
    );
    // RFC 6295 Figure A.9.1: |S|LEN| with LEN = logs - 1, then the logs.
    const bytes = [0x01, 0xBC, 0x0A, 0x3D, 0x8B];

    test('codes header and logs', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(chapter.length, 5);
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterA.read(MidiRtpByteReader(bytes)), chapter);
    });

    test('rejects an empty log list', () {
      expect(
        () => MidiRtpChapterA(logs: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith replaces the given fields', () {
      expect(chapter.copyWith(), chapter);
      final changed = chapter.copyWith(s: true, logs: chapter.logs.take(1));
      expect(changed.s, isTrue);
      expect(changed.logs, equals(chapter.logs.take(1)));
    });

    test('compares by value', () {
      final same = MidiRtpChapterA.read(MidiRtpByteReader(bytes));
      expect(chapter, same);
      expect(chapter.hashCode, same.hashCode);
      expect(chapter == chapter.copyWith(s: true), isFalse);
      expect(chapter == chapter.copyWith(logs: chapter.logs.take(1)), isFalse);
      expect(
        chapter.toString(),
        startsWith('MidiRtpChapterA(s: false, logs: ['),
      );
    });
  });
}
