// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterX', () {
    MidiRtpSysExLog log(bool s, int count) => MidiRtpSysExLog(
      s: s,
      count: count,
      data: [count],
      status: MidiRtpSysExStatus.finished,
    );
    final chapter = MidiRtpChapterX(logs: [log(false, 1), log(false, 2)]);
    // RFC 6295 B.5: the logs follow each other without a header.
    const bytes = [0x2B, 0x01, 0x81, 0x2B, 0x02, 0x82];

    test('codes the logs in a row', () {
      expect(chapter.toBytes(), equals(bytes));
      expect(chapter.s, isFalse);
    });

    test('reads logs up to the end of the system journal', () {
      expect(MidiRtpChapterX.read(MidiRtpByteReader(bytes)), chapter);
      expect(
        () => MidiRtpChapterX.read(MidiRtpByteReader(const [])),
        throwsA(isA<FormatException>()),
      );
    });

    group('isSafe(index)', () {
      test('derives the phantom S bit of the first log', () {
        // RFC 6295 B.5.1: one log: the chapter S bit; more logs: the OR of
        // the first two coded S bits.
        expect(MidiRtpChapterX(logs: [log(true, 1)]).isSafe(0), isTrue);
        expect(MidiRtpChapterX(logs: [log(false, 1)]).isSafe(0), isFalse);
        final two = MidiRtpChapterX(logs: [log(false, 1), log(true, 2)]);
        expect(two.isSafe(0), isTrue);
        expect(two.isSafe(1), isTrue);
        expect(chapter.isSafe(0), isFalse);
        expect(chapter.isSafe(1), isFalse);
      });
    });

    test('rejects an empty log list', () {
      expect(
        () => MidiRtpChapterX(logs: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('copyWith replaces the logs', () {
      expect(chapter.copyWith(), chapter);
      expect(
        chapter.copyWith(logs: [log(true, 3)]).logs,
        equals([log(true, 3)]),
      );
    });

    test('compares by value', () {
      final same = MidiRtpChapterX.read(MidiRtpByteReader(bytes));
      expect(chapter, same);
      expect(chapter.hashCode, same.hashCode);
      expect(chapter == chapter.copyWith(logs: [log(true, 3)]), isFalse);
      expect(chapter.toString(), startsWith('MidiRtpChapterX(logs: ['));
    });
  });
}
