// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChannelJournal', () {
    final chapterC = MidiRtpChapterC(
      logs: [
        const MidiRtpControllerLog(
          number: 7,
          tool: MidiRtpControllerTool.value,
          value: 100,
        ),
      ],
    );
    final chapterM = MidiRtpChapterM(e: true);
    final chapterN = MidiRtpChapterN(offNotes: [60]);
    final chapterE = MidiRtpChapterE(
      logs: [const MidiRtpNoteExtraLog(note: 60, v: true, value: 1)],
    );
    final chapterA = MidiRtpChapterA(
      logs: [const MidiRtpPressureLog(note: 60, pressure: 2)],
    );
    final journal = MidiRtpChannelJournal(
      s: false,
      channel: 9,
      h: true,
      chapterP: const MidiRtpChapterP(program: 1),
      chapterC: chapterC,
      chapterM: chapterM,
      chapterW: const MidiRtpChapterW(value: 0x2000),
      chapterN: chapterN,
      chapterE: chapterE,
      chapterT: const MidiRtpChapterT(pressure: 3),
      chapterA: chapterA,
    );
    // RFC 6295 Figure 9: |S|CHAN|H|LENGTH|P|C|M|W|N|E|T|A| and the chapters
    // in the order of the table of contents.
    const bytes = [
      0x4C, 0x17, 0xFF, //
      0x81, 0x00, 0x00, //
      0x80, 0x87, 0x64, //
      0xA0, 0x02, //
      0x80, 0x40, //
      0x80, 0x77, 0x08, //
      0x80, 0xBC, 0x81, //
      0x83, //
      0x80, 0xBC, 0x02, //
    ];

    group('toBytes()', () {
      test('codes header and chapters', () {
        expect(journal.toBytes(), equals(bytes));
        expect(
          const MidiRtpChannelJournal(channel: 0).toBytes(),
          equals([0x80, 0x03, 0x00]),
        );
      });

      test('rejects journals beyond 1023 octets', () {
        final big = MidiRtpChannelJournal(
          channel: 1,
          chapterC: MidiRtpChapterC(
            logs: [
              for (var n = 0; n < 128; n++)
                MidiRtpControllerLog(
                  number: n,
                  tool: MidiRtpControllerTool.value,
                  value: 0,
                ),
            ],
          ),
          chapterN: MidiRtpChapterN(
            logs: [
              for (var n = 0; n < 128; n++)
                MidiRtpNoteLog(note: n, velocity: 1),
            ],
          ),
          chapterE: MidiRtpChapterE(
            logs: [
              for (var n = 0; n < 128; n++)
                MidiRtpNoteExtraLog(note: n, v: true, value: 1),
            ],
          ),
          chapterA: MidiRtpChapterA(
            logs: [
              for (var n = 0; n < 128; n++)
                MidiRtpPressureLog(note: n, pressure: 1),
            ],
          ),
        );
        expect(
          big.toBytes,
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'Channel journal 1 is too long',
            ),
          ),
        );
      });
    });

    group('MidiRtpChannelJournal.read(reader)', () {
      test('decodes the journal', () {
        expect(MidiRtpChannelJournal.read(MidiRtpByteReader(bytes)), journal);
      });

      test('skips unknown octets up to LENGTH', () {
        final reader = MidiRtpByteReader([0x80, 0x05, 0x00, 0xEE, 0xEE, 0x77]);
        expect(
          MidiRtpChannelJournal.read(reader),
          const MidiRtpChannelJournal(channel: 0),
        );
        expect(reader.readUint8(), 0x77);
      });

      test('rejects a LENGTH below the header', () {
        expect(
          () =>
              MidiRtpChannelJournal.read(MidiRtpByteReader([0x80, 0x02, 0x00])),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'Channel journal LENGTH 2 is too small',
            ),
          ),
        );
      });

      test('fails on chapters beyond LENGTH', () {
        expect(
          () => MidiRtpChannelJournal.read(
            MidiRtpByteReader([0x80, 0x04, 0x80, 0x81, 0x00, 0x00]),
          ),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        const empty = MidiRtpChannelJournal(channel: 0);
        expect(journal.copyWith(), journal);
        expect(
          empty.copyWith(
            s: false,
            channel: 9,
            h: true,
            chapterP: journal.chapterP,
            chapterC: chapterC,
            chapterM: chapterM,
            chapterW: journal.chapterW,
            chapterN: chapterN,
            chapterE: chapterE,
            chapterT: journal.chapterT,
            chapterA: chapterA,
          ),
          journal,
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpChannelJournal.read(MidiRtpByteReader(bytes));
        expect(journal, same);
        expect(journal.hashCode, same.hashCode);
        const empty = MidiRtpChannelJournal(channel: 0);
        for (final other in [
          empty.copyWith(s: false),
          empty.copyWith(channel: 1),
          empty.copyWith(h: true),
          empty.copyWith(chapterP: journal.chapterP),
          empty.copyWith(chapterC: chapterC),
          empty.copyWith(chapterM: chapterM),
          empty.copyWith(chapterW: journal.chapterW),
          empty.copyWith(chapterN: chapterN),
          empty.copyWith(chapterE: chapterE),
          empty.copyWith(chapterT: journal.chapterT),
          empty.copyWith(chapterA: chapterA),
        ]) {
          expect(empty == other, isFalse);
        }
        expect(
          journal.toString(),
          startsWith('MidiRtpChannelJournal(s: false, channel: 9, h: true, '),
        );
      });
    });
  });
}
