// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpJournal', () {
    final journal = MidiRtpJournal(
      s: false,
      h: true,
      checkpoint: 0xABCD,
      systemJournal: const MidiRtpSystemJournal(
        chapterV: MidiRtpChapterV(count: 1),
      ),
      channelJournals: [
        const MidiRtpChannelJournal(
          channel: 2,
          chapterT: MidiRtpChapterT(pressure: 5),
        ),
        const MidiRtpChannelJournal(
          channel: 15,
          chapterW: MidiRtpChapterW(value: 0),
        ),
      ],
    );
    // RFC 6295 Figures 7 and 8: |S|Y|A|H|TOTCHAN|checkpoint|, the system
    // journal, then TOTCHAN + 1 channel journals.
    const bytes = [
      0x71, 0xAB, 0xCD, //
      0xA0, 0x03, 0x81, //
      0x90, 0x04, 0x02, 0x85, //
      0xF8, 0x05, 0x10, 0x80, 0x00, //
    ];

    group('toBytes()', () {
      test('codes header, system journal and channel journals', () {
        expect(journal.toBytes(), equals(bytes));
      });

      test('codes an empty journal as its header', () {
        final empty = MidiRtpJournal(checkpoint: 1);
        expect(empty.toBytes(), equals([0x80, 0x00, 0x01]));
        expect(empty.isEmpty, isTrue);
        expect(journal.isEmpty, isFalse);
        expect(
          MidiRtpJournal(
            checkpoint: 1,
            systemJournal: const MidiRtpSystemJournal(),
          ).isEmpty,
          isFalse,
        );
      });
    });

    group('MidiRtpJournal.read(reader)', () {
      test('decodes the journal', () {
        expect(MidiRtpJournal.read(MidiRtpByteReader(bytes)), journal);
      });

      test('ignores TOTCHAN without the A bit', () {
        expect(
          MidiRtpJournal.read(MidiRtpByteReader([0x8F, 0x00, 0x01])),
          MidiRtpJournal(checkpoint: 1),
        );
      });
    });

    group('MidiRtpJournal()', () {
      test('rejects channel journals out of order', () {
        expect(
          () => MidiRtpJournal(
            checkpoint: 0,
            channelJournals: const [
              MidiRtpChannelJournal(channel: 3),
              MidiRtpChannelJournal(channel: 3),
            ],
          ),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('channelJournal(channel)', () {
      test('finds the journal of a channel', () {
        expect(journal.channelJournal(15), journal.channelJournals.last);
        expect(journal.channelJournal(0), isNull);
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        final empty = MidiRtpJournal(checkpoint: 0);
        expect(journal.copyWith(), journal);
        expect(
          empty.copyWith(
            s: false,
            h: true,
            checkpoint: 0xABCD,
            systemJournal: journal.systemJournal,
            channelJournals: journal.channelJournals,
          ),
          journal,
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        final same = MidiRtpJournal.read(MidiRtpByteReader(bytes));
        expect(journal, same);
        expect(journal.hashCode, same.hashCode);
        final empty = MidiRtpJournal(checkpoint: 0);
        for (final other in [
          empty.copyWith(s: false),
          empty.copyWith(h: true),
          empty.copyWith(checkpoint: 1),
          empty.copyWith(systemJournal: journal.systemJournal),
          empty.copyWith(channelJournals: journal.channelJournals),
        ]) {
          expect(empty == other, isFalse);
        }
        expect(
          journal.toString(),
          startsWith('MidiRtpJournal(s: false, h: true, checkpoint: 43981, '),
        );
      });
    });
  });
}
