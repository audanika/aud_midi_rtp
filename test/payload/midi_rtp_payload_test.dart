// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpPayload', () {
    final journal = MidiRtpJournal(
      checkpoint: 0x0102,
      channelJournals: [
        const MidiRtpChannelJournal(
          channel: 0,
          chapterP: MidiRtpChapterP(program: 5),
        ),
      ],
    );
    final payload = MidiRtpPayload(
      commands: [
        const MidiRtpMessageCommand(
          message: MidiNoteOn(channel: 0, note: 60, velocity: 100),
        ),
      ],
      journal: journal,
    );
    // RFC 6295 2.2: command section (J = 1), then the journal.
    const bytes = [
      0x43, 0x90, 60, 100, //
      0xA0, 0x01, 0x02, //
      0x80, 0x06, 0x80, 0x85, 0x00, 0x00, //
    ];

    group('toBytes()', () {
      test('codes the command section and the journal', () {
        expect(payload.toBytes(), equals(bytes));
      });

      test('codes a payload without journal', () {
        expect(MidiRtpPayload().toBytes(), equals([0x00]));
        expect(MidiRtpPayload(phantom: true).toBytes(), equals([0x10]));
      });
    });

    group('MidiRtpPayload.decode(bytes)', () {
      test('decodes command section and journal', () {
        expect(MidiRtpPayload.decode(bytes), payload);
        expect(MidiRtpPayload.decode([0x10]), MidiRtpPayload(phantom: true));
      });

      test('fails on a missing journal', () {
        expect(
          () => MidiRtpPayload.decode([0x40]),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('MidiRtpPayload.read(reader)', () {
      test('stops after the journal', () {
        final reader = MidiRtpByteReader([...bytes, 0xEE]);
        expect(MidiRtpPayload.read(reader), payload);
        expect(reader.readUint8(), 0xEE);
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(payload.copyWith(), payload);
        final changed = payload.copyWith(
          commands: [],
          phantom: true,
          journal: MidiRtpJournal(checkpoint: 1),
        );
        expect(changed.commands, isEmpty);
        expect(changed.phantom, isTrue);
        expect(changed.journal, MidiRtpJournal(checkpoint: 1));
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        expect(payload, MidiRtpPayload.decode(bytes));
        expect(payload.hashCode, MidiRtpPayload.decode(bytes).hashCode);
        expect(payload == payload.copyWith(phantom: true), isFalse);
        expect(payload == payload.copyWith(commands: []), isFalse);
        expect(
          payload == payload.copyWith(journal: MidiRtpJournal(checkpoint: 1)),
          isFalse,
        );
        expect(payload.toString(), startsWith('MidiRtpPayload(commands: ['));
      });
    });
  });
}
