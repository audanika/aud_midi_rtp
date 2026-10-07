// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSystemJournal', () {
    final chapterX = MidiRtpChapterX(
      logs: [
        MidiRtpSysExLog(count: 1, status: MidiRtpSysExStatus.cancelled),
        MidiRtpSysExLog(
          count: 2,
          data: [5],
          status: MidiRtpSysExStatus.finished,
        ),
      ],
    );
    final journal = MidiRtpSystemJournal(
      s: false,
      chapterD: const MidiRtpChapterD(songSelect: (s: true, value: 4)),
      chapterV: const MidiRtpChapterV(count: 2),
      chapterQ: const MidiRtpChapterQ(n: true),
      chapterF: const MidiRtpChapterF(complete: 1),
      chapterX: chapterX,
    );
    // RFC 6295 Figure 10: |S|D|V|Q|F|X|LENGTH| and the chapters in the
    // order of the table of contents; Chapter X takes the rest.
    const bytes = [
      0x7C, 0x10, //
      0x90, 0x84, //
      0x82, //
      0xC0, //
      0xC7, 0, 0, 0, 1, //
      0xA1, 0x01, 0xAB, 0x02, 0x85, //
    ];

    group('toBytes()', () {
      test('codes header and chapters', () {
        expect(journal.toBytes(), equals(bytes));
        expect(const MidiRtpSystemJournal().toBytes(), equals([0x80, 0x02]));
      });

      test('rejects journals beyond 1023 octets', () {
        final big = MidiRtpSystemJournal(
          chapterX: MidiRtpChapterX(
            logs: [
              MidiRtpSysExLog(
                data: List.filled(1022, 1),
                status: MidiRtpSysExStatus.finished,
              ),
            ],
          ),
        );
        expect(
          big.toBytes,
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'System journal too long',
            ),
          ),
        );
      });
    });

    group('MidiRtpSystemJournal.read(reader)', () {
      test('decodes the journal', () {
        expect(MidiRtpSystemJournal.read(MidiRtpByteReader(bytes)), journal);
      });

      test('stops at LENGTH', () {
        final reader = MidiRtpByteReader([0x80, 0x02, 0x77]);
        expect(MidiRtpSystemJournal.read(reader), const MidiRtpSystemJournal());
        expect(reader.readUint8(), 0x77);
      });

      test('rejects a LENGTH below the header', () {
        expect(
          () => MidiRtpSystemJournal.read(MidiRtpByteReader([0x80, 0x01])),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'System journal LENGTH 1 is too small',
            ),
          ),
        );
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        const empty = MidiRtpSystemJournal();
        expect(journal.copyWith(), journal);
        expect(
          empty.copyWith(
            s: false,
            chapterD: journal.chapterD,
            chapterV: journal.chapterV,
            chapterQ: journal.chapterQ,
            chapterF: journal.chapterF,
            chapterX: chapterX,
          ),
          journal,
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpSystemJournal.read(MidiRtpByteReader(bytes));
        expect(journal, same);
        expect(journal.hashCode, same.hashCode);
        const empty = MidiRtpSystemJournal();
        for (final other in [
          empty.copyWith(s: false),
          empty.copyWith(chapterD: journal.chapterD),
          empty.copyWith(chapterV: journal.chapterV),
          empty.copyWith(chapterQ: journal.chapterQ),
          empty.copyWith(chapterF: journal.chapterF),
          empty.copyWith(chapterX: chapterX),
        ]) {
          expect(empty == other, isFalse);
        }
        expect(
          journal.toString(),
          startsWith('MidiRtpSystemJournal(s: false, chapterD: '),
        );
      });
    });
  });
}
