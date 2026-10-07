// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChapterN', () {
    final chapter = MidiRtpChapterN(
      logs: [const MidiRtpNoteLog(note: 60, velocity: 100)],
      offNotes: [72, 62, 64],
    );
    // RFC 6295 Figures A.6.1 to A.6.3: |B|LEN|LOW|HIGH|, the note logs and
    // the OFFBITS octets LOW to HIGH, the most significant bit for the
    // lowest note. Notes 62, 64 and 72 need the octets 7 to 9.
    const bytes = [0x81, 0x79, 0xBC, 0xE4, 0x02, 0x80, 0x80];

    group('toBytes()', () {
      test('codes header, logs and OFFBITS', () {
        expect(chapter.toBytes(), equals(bytes));
        expect(chapter.length, 7);
        expect(chapter.offNotes, equals([62, 64, 72]));
      });

      test('codes an empty NoteOff bitfield with LOW 15 and HIGH 1', () {
        final empty = MidiRtpChapterN(
          b: false,
          logs: [const MidiRtpNoteLog(note: 1, velocity: 1)],
        );
        expect(empty.toBytes(), equals([0x01, 0xF1, 0x81, 0x81]));
        expect(empty.length, 4);
      });

      test('codes 128 note logs with LEN 127, LOW 15 and HIGH 0', () {
        final full = MidiRtpChapterN(
          logs: [
            for (var n = 0; n < 128; n++) MidiRtpNoteLog(note: n, velocity: 1),
          ],
        );
        expect(full.toBytes().sublist(0, 2), equals([0xFF, 0xF0]));
        expect(MidiRtpChapterN.read(MidiRtpByteReader(full.toBytes())), full);
      });

      test('codes 127 note logs with LEN 127, LOW 15 and HIGH 1', () {
        final logs = [
          for (var n = 0; n < 127; n++) MidiRtpNoteLog(note: n, velocity: 1),
        ];
        final chapter = MidiRtpChapterN(logs: logs);
        expect(chapter.toBytes().sublist(0, 2), equals([0xFF, 0xF1]));
        expect(
          MidiRtpChapterN.read(MidiRtpByteReader(chapter.toBytes())),
          chapter,
        );
      });

      test('codes a bitfield without logs', () {
        final offs = MidiRtpChapterN(offNotes: [0, 127]);
        final encoded = offs.toBytes();
        expect(encoded.sublist(0, 3), equals([0x80, 0x0F, 0x80]));
        expect(encoded.last, 0x01);
        expect(encoded.length, 18);
      });
    });

    group('MidiRtpChapterN.read(reader)', () {
      test('decodes the chapter', () {
        expect(MidiRtpChapterN.read(MidiRtpByteReader(bytes)), chapter);
      });

      test('accepts LOW 15 and HIGH 0 with fewer logs', () {
        expect(
          MidiRtpChapterN.read(MidiRtpByteReader([0x00, 0xF0])),
          MidiRtpChapterN(b: false),
        );
      });

      test('rejects other LOW above HIGH', () {
        expect(
          () => MidiRtpChapterN.read(MidiRtpByteReader([0x00, 0x32])),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Illegal LOW 3 and HIGH 2 in Chapter N',
            ),
          ),
        );
      });
    });

    group('MidiRtpChapterN(b, logs, offNotes)', () {
      test('rejects OFFBITS beside 128 logs', () {
        expect(
          () => MidiRtpChapterN(
            logs: [
              for (var n = 0; n < 128; n++)
                MidiRtpNoteLog(note: n, velocity: 1),
            ],
            offNotes: [1],
          ),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(chapter.copyWith(), chapter);
        final changed = chapter.copyWith(b: false, logs: [], offNotes: [1]);
        expect(changed, MidiRtpChapterN(b: false, offNotes: [1]));
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpChapterN.read(MidiRtpByteReader(bytes));
        expect(chapter, same);
        expect(chapter.hashCode, same.hashCode);
        expect(chapter == chapter.copyWith(b: false), isFalse);
        expect(chapter == chapter.copyWith(logs: []), isFalse);
        expect(chapter == chapter.copyWith(offNotes: [1]), isFalse);
        expect(chapter.toString(), contains('offNotes: [62, 64, 72]'));
      });
    });
  });
}
