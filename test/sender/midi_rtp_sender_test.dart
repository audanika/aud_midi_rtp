// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSender', () {
    late List<String> issues;

    MidiRtpSender sender({
      MidiRtpSessionConfig config = MidiRtpSessionConfig.appleMidi,
      int sequenceNumber = 100,
      int? maxJournalLength,
      int openLoopWindow = 64,
    }) => MidiRtpSender(
      config: config,
      ssrc: 0x11223344,
      sequenceNumber: sequenceNumber,
      maxJournalLength: maxJournalLength,
      openLoopWindow: openLoopWindow,
      onIssue: (kind, cause) => issues.add('${kind.name}: $cause'),
    );

    MidiTimedMessage at(MidiMessage message, int microseconds) =>
        (message: message, time: MidiTime(microseconds));

    setUp(() => issues = []);

    group('send(messages)', () {
      test('codes header, command section and journal', () {
        final s = sender();
        final packets = s.send([
          at(const MidiNoteOn(channel: 0, note: 60, velocity: 100), 1000),
          at(const MidiNoteOn(channel: 0, note: 62, velocity: 90), 1500),
        ]);
        expect(packets, hasLength(1));
        // 10 kHz: 1000 us = 10 units; the second note 5 units later with
        // running status; an empty journal with checkpoint 100.
        expect(
          packets.single.toBytes(),
          equals([
            0x80, 0xE1, 0x00, 0x64, 0x00, 0x00, 0x00, 0x0A, //
            0x11, 0x22, 0x33, 0x44, //
            0x46, 0x90, 0x3C, 0x64, 0x05, 0x3E, 0x5A, //
            0x80, 0x00, 0x64, //
          ]),
        );
        expect(s.sequenceNumber, 101);
        expect(s.extendedSequenceNumber, 101);
        expect(s.journalLength, 3);
        expect(s.history.channels[0].note(60)!.seq, 100);
      });

      test('journals the previous packets', () {
        final s = sender();
        s.send([at(const MidiProgramChange(channel: 1, program: 7), 0)]);
        final packet = s.send([at(const MidiTimingClock(), 10)]).single;
        final journal = packet.payload.journal!;
        expect(journal.checkpoint, 100);
        expect(journal.s, isFalse);
        expect(
          journal.channelJournals.single.chapterP,
          const MidiRtpChapterP(s: false, program: 7),
        );
      });

      test('returns no packet for nothing to send', () {
        expect(sender().send([]), isEmpty);
      });

      test('clamps times that go backwards', () {
        final s = sender();
        final packets = s.send([
          at(const MidiTimingClock(), 2000),
          at(const MidiTimingClock(), 1000),
        ]);
        expect(packets.single.header.timestamp, 20);
        expect(packets.single.payload.commands.last.deltaTime, 0);
        expect(s.send([at(const MidiStart(), 0)]).single.header.timestamp, 20);
      });

      test('skips messages without a MIDI 1.0 byte form', () {
        final s = sender();
        expect(
          s.send([at(const MidiNoteOn2(channel: 0, note: 1, velocity: 2), 0)]),
          isEmpty,
        );
        expect(issues.single, startsWith('untranslatable: RTP MIDI carries'));
      });

      test('skips command types the configuration excludes', () {
        final s = sender(
          config: MidiRtpSessionConfig.fromFmtp(
            MidiRtpFmtp.parse(
              'a=fmtp:97 cm_unused=ABFGHMNPQTVW; cm_unused=C7; '
              'cm_unused=__7E__',
            ),
            clockRate: 10000,
          ),
        );
        final packets = s.send([
          for (final m in <MidiMessage>[
            const MidiNoteOn(channel: 0, note: 1, velocity: 1),
            const MidiNoteOff(channel: 0, note: 1),
            const MidiPolyPressure(channel: 0, note: 1, pressure: 1),
            const MidiControlChange(channel: 0, controller: 7, value: 1),
            const MidiControlChange(channel: 0, controller: 101, value: 1),
            const MidiProgramChange(channel: 0, program: 1),
            const MidiChannelPressure(channel: 0, pressure: 1),
            const MidiPitchBend(channel: 0, value: 1),
            const MidiTimeCodeQuarterFrame(piece: 1, value: 1),
            const MidiTuneRequest(),
            const MidiSongSelect(song: 1),
            const MidiActiveSensing(),
            const MidiSystemReset(),
            const MidiTimingClock(),
            MidiSysEx([0x7E, 1]),
          ])
            at(m, 0),
          at(const MidiControlChange(channel: 0, controller: 8, value: 1), 0),
          at(MidiSysEx([0x7D]), 0),
        ]);
        expect(issues, hasLength(15));
        expect(
          [for (final c in packets.single.payload.commands) c.octets],
          equals([
            [0xB0, 8, 1],
            [0xF0, 0x7D, 0xF7],
          ]),
        );
      });

      test('classifies data entry by the selection of the history', () {
        final s = sender(
          config: MidiRtpSessionConfig.fromFmtp(
            MidiRtpFmtp.parse('a=fmtp:97 cm_unused=M'),
            clockRate: 10000,
          ),
        );
        s.history.apply(
          const MidiControlChange(channel: 2, controller: 101, value: 0),
        );
        expect(
          s.send([
            at(const MidiControlChange(channel: 2, controller: 6, value: 1), 0),
          ]),
          isEmpty,
        );
        expect(
          s.send([
            at(const MidiControlChange(channel: 3, controller: 6, value: 1), 0),
          ]),
          hasLength(1),
        );
      });

      test('starts a new packet beyond the largest delta time', () {
        final packets = sender().send([
          at(const MidiTimingClock(), 0),
          at(const MidiTimingClock(), 27000000000),
        ]);
        expect(packets, hasLength(2));
        expect(packets[1].header.timestamp, 270000000);
      });

      test('starts a new packet beyond rtp_maxptime', () {
        final s = sender(
          config: MidiRtpSessionConfig.appleMidi.copyWith(maxPacketTime: 10),
        );
        final packets = s.send([
          at(const MidiTimingClock(), 0),
          at(const MidiTimingClock(), 1000),
          at(const MidiTimingClock(), 1100),
        ]);
        expect([
          for (final p in packets) p.payload.commands.length,
        ], equals([2, 1]));
      });

      test('splits commands over packets of the maximum size', () {
        final s = sender(
          config: MidiRtpSessionConfig.appleMidi.copyWith(maxPacketSize: 64),
        );
        // Timing clocks of a stopped sequencer change no journal state: 47
        // octets remain for one clock and 23 clocks with delta times.
        final packets = s.send([
          for (var i = 0; i < 40; i++) at(const MidiTimingClock(), 0),
        ]);
        expect([
          for (final p in packets) p.payload.commands.length,
        ], equals([24, 16]));
        for (final packet in packets) {
          expect(packet.toBytes().length, lessThanOrEqualTo(64));
        }
      });

      test('segments System Exclusive over packets', () {
        final s = sender(
          config: MidiRtpSessionConfig.appleMidi.copyWith(maxPacketSize: 64),
        );
        final data = [for (var i = 0; i < 200; i++) i & 0x7F];
        final packets = s.send([
          at(const MidiTimingClock(), 0),
          at(MidiSysEx(data), 0),
          at(const MidiTimingClock(), 0),
        ]);
        final segments = [
          for (final p in packets)
            for (final c in p.payload.commands)
              if (c is MidiRtpSysExCommand) c,
        ];
        expect(
          segments.map((c) => c.kind),
          equals([
            MidiRtpSysExKind.first,
            MidiRtpSysExKind.middle,
            MidiRtpSysExKind.middle,
            MidiRtpSysExKind.last,
          ]),
        );
        expect([for (final c in segments) ...c.data], equals(data));
        expect(
          packets.last.payload.commands.last,
          isA<MidiRtpMessageCommand>(),
        );
        expect(s.history.system.sysEx.single.data, equals(data));
      });

      test('forces progress when the journal leaves no room', () {
        final s = sender(
          config: MidiRtpSessionConfig.appleMidi.copyWith(maxPacketSize: 64),
        );
        s.send([at(MidiSysEx(List.filled(70, 1)), 0)]);
        final packets = s.send([
          at(MidiSysEx(List.filled(70, 2)), 0),
          at(const MidiTuneRequest(), 0),
        ]);
        expect(
          [
            for (final p in packets)
              [for (final c in p.payload.commands) c.runtimeType],
          ].first,
          equals([MidiRtpSysExCommand]),
        );
        final first = packets.first.payload.commands.single;
        expect((first as MidiRtpSysExCommand).data, hasLength(64));
        expect(
          packets.last.payload.commands.last,
          isA<MidiRtpMessageCommand>(),
        );
        final small = s.send([at(const MidiTuneRequest(), 0)]);
        expect(small.single.payload.commands, hasLength(1));
      });
    });

    group('guard(time)', () {
      test('sends an empty packet with the journal', () {
        final s = sender();
        s.send([at(const MidiNoteOn(channel: 0, note: 1, velocity: 1), 500)]);
        final guard = s.guard(time: const MidiTime(2000));
        expect(guard.header.marker, isFalse);
        expect(guard.header.timestamp, 20);
        expect(guard.payload.commands, isEmpty);
        expect(guard.payload.journal!.channelJournals, hasLength(1));
        expect(s.guard(time: MidiTime.zero).header.timestamp, 20);
      });
    });

    group('acknowledge(sequenceNumber)', () {
      test('moves the closed-loop checkpoint and trims the history', () {
        final s = sender(
          config: MidiRtpSessionConfig.fromFmtp(
            MidiRtpFmtp.parse('a=fmtp:97 ch_default=C135'),
            clockRate: 10000,
          ),
        );
        s.acknowledge(100);
        expect(s.acknowledged, isNull);
        s.send([
          at(MidiSysEx([1]), 0),
        ]);
        s.send([
          at(const MidiControlChange(channel: 0, controller: 7, value: 1), 0),
        ]);
        expect(s.checkpoint, 100);
        s.acknowledge(101);
        expect(s.acknowledged, 101);
        expect(s.checkpoint, 102);
        expect(s.history.system.sysEx, isEmpty);
        expect(s.history.channels[0].controllerHistory(7), isEmpty);
        expect(s.guard(time: MidiTime.zero).payload.journal!.isEmpty, isTrue);
        s.acknowledge(100);
        expect(s.acknowledged, 101);
      });

      test('extends the sequence number over the wrap', () {
        final s = sender(sequenceNumber: 0xFFFE);
        for (var i = 0; i < 4; i++) {
          s.guard(time: MidiTime.zero);
        }
        s.acknowledge(0x0000);
        expect(s.acknowledged, 0x10000);
        expect(s.checkpoint, 0x10001);
        s.acknowledge(0xFFFD);
        expect(s.acknowledged, 0x10000);
      });

      test('keeps anchored history', () {
        final s = sender(
          config: MidiRtpSessionConfig.fromFmtp(
            MidiRtpFmtp.parse('a=fmtp:97 ch_anchor=C135; ch_anchor=__05__'),
            clockRate: 10000,
          ),
        );
        s.send([
          at(const MidiControlChange(channel: 0, controller: 7, value: 1), 0),
          at(MidiSysEx([5]), 0),
          at(MidiSysEx([6]), 0),
        ]);
        s.acknowledge(100);
        expect(s.history.channels[0].controllerHistory(7), hasLength(1));
        expect(s.history.system.sysEx.single.data, equals([5]));
        final journal = s.guard(time: MidiTime.zero).payload.journal!;
        expect(journal.channelJournals.single.chapterC, isNotNull);
        expect(journal.systemJournal!.chapterX!.logs.single.count, 1);
      });
    });

    group('sending policies', () {
      test('anchor keeps the first packet as checkpoint', () {
        final s = sender(
          config: MidiRtpSessionConfig.appleMidi.copyWith(
            sendingPolicy: MidiRtpSendingPolicy.anchor,
          ),
        );
        s.send([
          at(MidiSysEx([1]), 0),
        ]);
        s.guard(time: MidiTime.zero);
        s.acknowledge(101);
        expect(s.checkpoint, 100);
        expect(s.history.system.sysEx, hasLength(1));
      });

      test('open-loop slides a window over the stream', () {
        final s = sender(
          config: MidiRtpSessionConfig.appleMidi.copyWith(
            sendingPolicy: MidiRtpSendingPolicy.openLoop,
          ),
          openLoopWindow: 2,
        );
        s.send([
          at(MidiSysEx([1]), 0),
        ]);
        expect(s.checkpoint, 100);
        s.guard(time: MidiTime.zero);
        s.guard(time: MidiTime.zero);
        expect(s.checkpoint, 101);
        expect(s.history.system.sysEx, isEmpty);
        s.acknowledge(102);
        expect(s.checkpoint, 103);
        expect(s.openLoopWindow, 2);
      });
    });

    group('journal bound', () {
      test('drops the history beyond maxJournalLength', () {
        final s = sender(maxJournalLength: 20);
        s.send([at(MidiSysEx(List.filled(30, 1)), 0)]);
        final packet = s.guard(time: MidiTime.zero);
        expect(packet.payload.journal!.isEmpty, isTrue);
        expect(s.journalLength, 3);
        expect(s.acknowledged, 100);
        expect(issues.single, startsWith('networkLoss: The journal of packet'));
        expect(s.maxJournalLength, 20);
      });

      test('sends no journal without j_sec recj', () {
        final s = sender(
          config: MidiRtpSessionConfig.appleMidi.copyWith(journal: false),
        );
        final packet = s.send([at(const MidiStart(), 0)]).single;
        expect(packet.payload.journal, isNull);
        expect(s.journalLength, 0);
        expect(packet.toBytes().sublist(12), equals([0x01, 0xFA]));
      });
    });

    group('fields', () {
      test('hold the construction arguments', () {
        final s = sender();
        expect(s.config, MidiRtpSessionConfig.appleMidi);
        expect(s.ssrc, 0x11223344);
        expect(s.clock, const MidiRtpClock(rate: 10000));
        expect(s.onIssue, isNotNull);
        expect(MidiRtpSender(ssrc: 1).clock, const MidiRtpClock(rate: 10000));
      });
    });
  });
}
