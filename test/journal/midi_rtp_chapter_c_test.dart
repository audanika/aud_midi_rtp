// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterC', () {
    final chapter = MidiRtpChapterC(
      s: false,
      logs: [
        const MidiRtpControllerLog(
          number: 7,
          tool: MidiRtpControllerTool.value,
          value: 100,
        ),
        const MidiRtpControllerLog(
          s: false,
          number: 64,
          tool: MidiRtpControllerTool.toggle,
          value: 3,
        ),
      ],
    );
    // RFC 6295 Figure A.3.1: |S|LEN| with LEN = logs - 1, then the logs.
    const bytes = [0x01, 0x87, 0x64, 0x40, 0x83];

    test('codes the header and the logs', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(chapter.length, 5);
    });

    test('decodes the chapter', () {
      expect(MidiRtpChapterC.read(MidiRtpByteReader(bytes)), chapter);
    });

    test('codes 128 logs with LEN 127', () {
      final full = MidiRtpChapterC(
        logs: [
          for (var n = 0; n < 128; n++)
            MidiRtpControllerLog(
              number: n,
              tool: MidiRtpControllerTool.value,
              value: n,
            ),
        ],
      );
      expect(full.toBytes()[0], 0xFF);
      expect(MidiRtpChapterC.read(MidiRtpByteReader(full.toBytes())), full);
    });

    test('rejects an empty log list', () {
      expect(
        () => MidiRtpChapterC(logs: const []),
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
      final same = MidiRtpChapterC.read(MidiRtpByteReader(bytes));
      expect(chapter, same);
      expect(chapter.hashCode, same.hashCode);
      expect(chapter == chapter.copyWith(s: true), isFalse);
      expect(chapter == chapter.copyWith(logs: chapter.logs.take(1)), isFalse);
      expect(
        chapter.toString(),
        startsWith('MidiRtpChapterC(s: false, logs: ['),
      );
    });
  });
}
