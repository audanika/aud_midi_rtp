// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpJournalBuilder', () {
    late MidiRtpStreamState history;
    late MidiRtpJournalBuilder builder;
    late List<String> issues;

    MidiRtpSessionConfig config(String fmtp) => MidiRtpSessionConfig.fromFmtp(
      MidiRtpFmtp.parse('a=fmtp:97 $fmtp'),
      clockRate: 10000,
    );

    void use(MidiRtpSessionConfig c) {
      builder = MidiRtpJournalBuilder(
        config: c,
        onIssue: (kind, cause) => issues.add('${kind.name}: $cause'),
      );
      history = MidiRtpStreamState(
        isEnhanced: c.isEnhanced,
        countsSysEx: (data) =>
            c.sysExSemantics(data) != MidiRtpChapterSemantics.never,
      );
    }

    setUp(() {
      issues = [];
      use(MidiRtpSessionConfig.appleMidi);
    });

    MidiRtpJournal build({
      int seq = 10,
      int checkpoint = 5,
      int first = 1,
      int time = 0,
    }) => builder.build(
      history,
      seq: seq,
      checkpoint: checkpoint,
      first: first,
      time: MidiTime(time),
    );

    void apply(MidiMessage message, {int seq = 9, int time = 0}) =>
        history.apply(message, seq: seq, time: MidiTime(time));
    void cc(int controller, int value, {int channel = 0, int seq = 9}) => apply(
      MidiControlChange(channel: channel, controller: controller, value: value),
      seq: seq,
    );

    group('build(history, seq, checkpoint, first, time)', () {
      test('returns an empty journal for an empty history', () {
        final journal = build(checkpoint: 0x12345);
        expect(journal, MidiRtpJournal(checkpoint: 0x2345));
        expect(journal.toBytes(), equals([0x80, 0x23, 0x45]));
        expect(builder.recentNoteOn, const Duration(milliseconds: 100));
        expect(builder.config, MidiRtpSessionConfig.appleMidi);
      });

      test('codes only the packets from the checkpoint', () {
        apply(const MidiProgramChange(channel: 0, program: 1), seq: 4);
        apply(const MidiProgramChange(channel: 1, program: 2), seq: 5);
        final journal = build();
        expect(journal.channelJournals.single.channel, 1);
        expect(journal.s, isTrue);
      });

      test('clears the S bits of elements of the previous packet', () {
        apply(const MidiProgramChange(channel: 0, program: 1), seq: 9);
        apply(const MidiPitchBend(channel: 0, value: 5), seq: 8);
        final journal = build();
        final channel = journal.channelJournals.single;
        expect(journal.s, isFalse);
        expect(channel.s, isFalse);
        expect(channel.chapterP!.s, isFalse);
        expect(channel.chapterW!.s, isTrue);
      });
    });

    group('channel chapters', () {
      test('code P, W and T', () {
        cc(0, 3);
        cc(32, 4);
        apply(const MidiProgramChange(channel: 0, program: 5));
        apply(const MidiPitchBend(channel: 0, value: 0x1234));
        apply(const MidiChannelPressure(channel: 0, pressure: 6));
        final channel = build(seq: 11).channelJournals.single;
        expect(
          channel.chapterP,
          const MidiRtpChapterP(program: 5, b: true, bankMsb: 3, bankLsb: 4),
        );
        expect(channel.chapterW, const MidiRtpChapterW(value: 0x1234));
        expect(channel.chapterT, const MidiRtpChapterT(pressure: 6));
      });

      test('code controllers with their tools, oldest first', () {
        cc(7, 100);
        cc(64, 127);
        cc(1, 5);
        cc(123, 0);
        final logs = build(seq: 11).channelJournals.single.chapterC!.logs;
        expect(
          [for (final log in logs) (log.number, log.tool, log.value)],
          equals([
            (7, MidiRtpControllerTool.value, 100),
            (64, MidiRtpControllerTool.count, 1),
            (64, MidiRtpControllerTool.value, 127),
            (64, MidiRtpControllerTool.toggle, 1),
            (1, MidiRtpControllerTool.count, 1),
            (1, MidiRtpControllerTool.value, 5),
            (123, MidiRtpControllerTool.count, 1),
            (123, MidiRtpControllerTool.value, 0),
          ]),
        );
      });

      test('code every recent command of enhanced controllers', () {
        use(config('ch_default=0C144'));
        cc(16, 1, seq: 4);
        cc(16, 2, seq: 6);
        cc(16, 3, seq: 9);
        final journal = build();
        expect(journal.h, isTrue);
        final channel = journal.channelJournals.single;
        expect(channel.h, isTrue);
        expect(
          [
            for (final log in channel.chapterC!.logs)
              (log.s, log.tool, log.value),
          ],
          equals([
            (true, MidiRtpControllerTool.count, 2),
            (true, MidiRtpControllerTool.value, 2),
            (false, MidiRtpControllerTool.count, 3),
            (false, MidiRtpControllerTool.value, 3),
          ]),
        );
      });

      test('use one tool per command beyond 128 logs', () {
        for (var c = 0; c < 128; c++) {
          if (c >= 98 && c <= 101) continue;
          cc(c, 1);
        }
        final logs = build(seq: 11).channelJournals.single.chapterC!.logs;
        expect(logs, hasLength(126));
        expect(logs.where((l) => l.number == 64), hasLength(1));
        expect(
          [
            for (final l in logs.where((l) => l.number >= 120))
              (l.number, l.tool),
          ],
          equals([
            (120, MidiRtpControllerTool.count),
            (121, MidiRtpControllerTool.count),
            (122, MidiRtpControllerTool.count),
            (122, MidiRtpControllerTool.value),
            (123, MidiRtpControllerTool.count),
            (124, MidiRtpControllerTool.count),
            (125, MidiRtpControllerTool.count),
            (126, MidiRtpControllerTool.count),
            (126, MidiRtpControllerTool.value),
            (127, MidiRtpControllerTool.count),
          ]),
        );
        expect(issues, isEmpty);
      });

      test('leave out the oldest logs beyond 128 enhanced logs', () {
        use(config('ch_default=0C136'));
        for (var i = 0; i < 70; i++) {
          cc(8, i & 0x7F);
        }
        final logs = build(seq: 11).channelJournals.single.chapterC!.logs;
        expect(logs, hasLength(128));
        expect(logs.last.value, 69);
        expect(
          issues.single,
          startsWith('queueOverflow: Chapter C of channel 0'),
        );
      });

      test('code notes with Y bits and the B bit', () {
        apply(const MidiNoteOn(channel: 2, note: 60, velocity: 90), time: 0);
        apply(
          const MidiNoteOn(channel: 2, note: 61, velocity: 91),
          time: 200000,
        );
        apply(const MidiNoteOff(channel: 2, note: 62), seq: 8);
        final channel = build(time: 250000).channelJournals.single;
        expect(
          channel.chapterN,
          MidiRtpChapterN(
            logs: [
              const MidiRtpNoteLog(s: false, note: 60, y: false, velocity: 90),
              const MidiRtpNoteLog(s: false, note: 61, velocity: 91),
            ],
            offNotes: [62],
          ),
        );
        apply(const MidiNoteOff(channel: 2, note: 63));
        expect(build().channelJournals.single.chapterN!.b, isFalse);
      });

      test('code note extras', () {
        apply(const MidiNoteOn(channel: 0, note: 60, velocity: 1));
        apply(const MidiNoteOn(channel: 0, note: 60, velocity: 2));
        apply(const MidiNoteOn(channel: 0, note: 61, velocity: 1));
        apply(const MidiNoteOn(channel: 0, note: 61, velocity: 2));
        apply(const MidiNoteOff(channel: 0, note: 61, velocity: 30));
        apply(const MidiNoteOff(channel: 0, note: 62, velocity: 64));
        expect(
          build(seq: 11).channelJournals.single.chapterE,
          MidiRtpChapterE(
            logs: [
              const MidiRtpNoteExtraLog(note: 60, v: false, value: 2),
              const MidiRtpNoteExtraLog(note: 61, v: false, value: 1),
              const MidiRtpNoteExtraLog(note: 61, v: true, value: 30),
            ],
          ),
        );
      });

      test('caps note extras at 128 logs, dropping release velocities', () {
        for (var note = 0; note < 128; note++) {
          apply(MidiNoteOn(channel: 0, note: note, velocity: 1));
          apply(MidiNoteOn(channel: 0, note: note, velocity: 1));
          apply(MidiNoteOff(channel: 0, note: note, velocity: 1));
        }
        final logs = build(seq: 11).channelJournals.single.chapterE!.logs;
        expect(logs, hasLength(128));
        expect(logs.every((log) => !log.v), isTrue);
      });

      test('code poly aftertouch with the X bit', () {
        apply(const MidiPolyPressure(channel: 0, note: 60, pressure: 1));
        cc(123, 0);
        apply(const MidiPolyPressure(channel: 0, note: 61, pressure: 2));
        expect(
          build(seq: 11).channelJournals.single.chapterA,
          MidiRtpChapterA(
            logs: [
              const MidiRtpPressureLog(note: 60, x: true, pressure: 1),
              const MidiRtpPressureLog(note: 61, pressure: 2),
            ],
          ),
        );
      });
    });

    group('Chapter M', () {
      test('codes values, the transaction in progress and short headers', () {
        cc(101, 0, seq: 3);
        cc(100, 1, seq: 3);
        cc(6, 9, seq: 3);
        cc(38, 8, seq: 6);
        cc(96, 0, seq: 6);
        cc(121, 0, seq: 7);
        cc(97, 0, seq: 7);
        cc(101, 0, seq: 8);
        cc(100, 2, seq: 8);
        final m = build().channelJournals.single.chapterM!;
        expect(
          m,
          MidiRtpChapterM(
            e: true,
            u: true,
            z: true,
            logs: [
              const MidiRtpParameterLog(
                number: 1,
                entryMsb: (value: 9, x: true),
                entryLsb: (value: 8, x: true),
                aButton: (count: 1, x: true),
                cButton: 0,
              ),
              const MidiRtpParameterLog(number: 2),
            ],
          ),
        );
      });

      test('codes NRPN logs and a pending MSB', () {
        cc(99, 1, seq: 6);
        cc(98, 2, seq: 6);
        cc(6, 3, seq: 6);
        cc(101, 4, seq: 9);
        final m = build().channelJournals.single.chapterM!;
        expect(m.s, isFalse);
        expect(m.pending, (value: 4, nrpn: false));
        expect(m.e, isFalse);
        expect(m.w, isTrue);
        expect(m.z, isFalse);
        expect(m.logs.single.number, 1 << 7 | 2);
      });

      test('codes the current transaction even when it is older', () {
        use(config('ch_anchor=M5'));
        cc(101, 0, seq: 2);
        cc(100, 5, seq: 2);
        cc(6, 1, seq: 2);
        cc(101, 0, seq: 3);
        cc(100, 1, seq: 3);
        final m = build().channelJournals.single.chapterM!;
        expect(m.e, isTrue);
        expect(m.logs.map((l) => l.number), equals([5, 1]));
        cc(101, 127, seq: 4);
        cc(100, 127, seq: 4);
        expect(
          build().channelJournals.single.chapterM!.logs.map((l) => l.number),
          equals([5]),
        );
      });

      test('codes a closed selection without logs', () {
        cc(101, 127, seq: 9);
        cc(100, 127, seq: 9);
        expect(
          build().channelJournals.single.chapterM,
          MidiRtpChapterM(s: false),
        );
      });

      test('honours ch_never and keeps the transaction in progress', () {
        use(config('ch_never=M'));
        cc(101, 0, seq: 6);
        cc(100, 1, seq: 6);
        cc(6, 5, seq: 6);
        expect(
          build().channelJournals.single.chapterM,
          MidiRtpChapterM(
            e: true,
            u: true,
            z: true,
            logs: [const MidiRtpParameterLog(number: 1, v: false)],
          ),
        );
        cc(101, 127, seq: 7);
        cc(100, 127, seq: 7);
        expect(build().channelJournals, isEmpty);
        expect(build(checkpoint: 8).channelJournals, isEmpty);
      });
    });

    group('ch_anchor and ch_never', () {
      test('cover the session history or nothing', () {
        use(config('ch_anchor=P; ch_never=W'));
        apply(const MidiProgramChange(channel: 0, program: 1), seq: 1);
        apply(const MidiPitchBend(channel: 0, value: 1), seq: 9);
        final channel = build().channelJournals.single;
        expect(channel.chapterP!.program, 1);
        expect(channel.chapterW, isNull);
      });
    });

    group('system chapters', () {
      test('code D and V', () {
        use(config('cm_used=JKYZ'));
        apply(const MidiSystemReset());
        apply(const MidiTuneRequest(), seq: 8);
        apply(const MidiSongSelect(song: 7), seq: 8);
        apply(const MidiActiveSensing(), seq: 7);
        history
          ..applyUndefined(0xF4, const [], seq: 9)
          ..applyUndefined(0xF5, const [1, 2], seq: 9)
          ..applyUndefined(0xF9, const [], seq: 9)
          ..applyUndefined(0xFD, const [], seq: 6);
        final system = build().systemJournal!;
        expect(
          system.chapterD,
          MidiRtpChapterD(
            s: false,
            reset: (s: false, value: 1),
            tuneRequest: (s: true, value: 1),
            songSelect: (s: true, value: 7),
            f4: MidiRtpUndefinedCommonLog(s: false, dsz: 0, count: 1),
            f5: MidiRtpUndefinedCommonLog(
              s: false,
              dsz: 2,
              count: 1,
              value: [1, 2],
            ),
            f9: MidiRtpUndefinedRealTimeLog(s: false, count: 1),
            fd: MidiRtpUndefinedRealTimeLog(count: 1),
          ),
        );
        expect(system.chapterV, const MidiRtpChapterV(count: 1));
        expect(system.s, isFalse);
      });

      test('code the sequencer state in Q', () {
        apply(const MidiStart(), seq: 6);
        expect(build().systemJournal!.chapterQ, const MidiRtpChapterQ(n: true));
        apply(const MidiStop(), seq: 6);
        apply(const MidiContinue(), seq: 6);
        expect(
          build().systemJournal!.chapterQ,
          const MidiRtpChapterQ(n: true, position: 0),
        );
        apply(const MidiTimingClock(), seq: 6);
        apply(const MidiTimingClock(), seq: 6);
        apply(const MidiStop(), seq: 9);
        expect(
          build().systemJournal!.chapterQ,
          const MidiRtpChapterQ(s: false, d: true, position: 1),
        );
      });

      test('code the time code in F', () {
        const code = MidiRtpTimeCode(hours: 1);
        final nibbles = code.toNibbles();
        for (var piece = 0; piece < 8; piece++) {
          apply(
            MidiTimeCodeQuarterFrame(piece: piece, value: nibbles[piece]),
            seq: 6,
          );
        }
        apply(MidiTimeCodeQuarterFrame(piece: 0, value: nibbles[0]), seq: 6);
        expect(
          build().systemJournal!.chapterF,
          MidiRtpChapterF(
            complete: code.advance(2).toField(nibbles: true),
            q: true,
            point: 0,
            partial: nibbles[0] << 28,
          ),
        );
        apply(const MidiTimeCodeQuarterFrame(piece: 7, value: 0), seq: 6);
        expect(build().systemJournal!.chapterF!.point, 7);
        apply(const MidiTimeCodeQuarterFrame(piece: 6, value: 0), seq: 6);
        apply(const MidiTimeCodeQuarterFrame(piece: 3, value: 0), seq: 6);
        expect(
          build().systemJournal!.chapterF,
          MidiRtpChapterF(
            complete: code.advance(2).toField(nibbles: true),
            q: true,
            d: true,
            point: 0,
          ),
        );
      });

      test('code System Exclusive in X', () {
        history
          ..applySysEx(MidiRtpSysExKind.complete, [1], seq: 3)
          ..applySysEx(MidiRtpSysExKind.complete, [2, 3], seq: 6)
          ..applySysEx(MidiRtpSysExKind.first, [4], seq: 3)
          ..applySysEx(MidiRtpSysExKind.middle, [5], seq: 4)
          ..applySysEx(MidiRtpSysExKind.middle, [6], seq: 6)
          ..applySysEx(MidiRtpSysExKind.last, [], droppedF7: true, seq: 7)
          ..applySysEx(MidiRtpSysExKind.first, [7], seq: 7)
          ..applySysEx(MidiRtpSysExKind.cancel, [], seq: 8)
          ..applySysEx(MidiRtpSysExKind.first, [8], seq: 4)
          ..applySysEx(MidiRtpSysExKind.last, [], seq: 9);
        expect(
          build().systemJournal!.chapterX,
          MidiRtpChapterX(
            logs: [
              MidiRtpSysExLog(
                s: false,
                count: 2,
                data: [2, 3],
                status: MidiRtpSysExStatus.finished,
              ),
              MidiRtpSysExLog(
                count: 3,
                first: 2,
                data: [6],
                status: MidiRtpSysExStatus.droppedF7,
              ),
              MidiRtpSysExLog(count: 4, status: MidiRtpSysExStatus.cancelled),
              MidiRtpSysExLog(
                s: false,
                count: 5,
                first: 1,
                status: MidiRtpSysExStatus.finished,
              ),
            ],
          ),
        );
      });

      test('code finished Full Frames and leave out ch_never classes', () {
        use(config('ch_never=__7D__'));
        apply(MidiSysEx([0x7D, 1]), seq: 9);
        apply(MidiSysEx([0x7F, 0x7F, 1, 1, 0, 0, 0, 0]), seq: 9);
        final system = build().systemJournal!;
        expect(system.chapterX!.logs.single.count, 1);
        expect(system.chapterF!.complete, 0);
      });
    });

    group('journal size', () {
      test(
        'leaves out the oldest System Exclusive logs beyond 1023 octets',
        () {
          history
            ..applySysEx(MidiRtpSysExKind.complete, List.filled(600, 1), seq: 6)
            ..applySysEx(
              MidiRtpSysExKind.complete,
              List.filled(600, 2),
              seq: 6,
            );
          final x = build().systemJournal!.chapterX!;
          expect(x.logs.single.data!.first, 2);
          expect(issues.single, startsWith('sysExTooLong: The system journal'));
          history.applySysEx(
            MidiRtpSysExKind.complete,
            List.filled(1100, 3),
            seq: 6,
          );
          expect(build().systemJournal, isNull);
        },
      );

      test('leaves out the oldest parameter and controller logs', () {
        for (var n = 0; n < 128; n++) {
          if (n >= 98 && n <= 101) continue;
          cc(n, 0);
        }
        for (var note = 0; note < 128; note++) {
          apply(MidiNoteOn(channel: 0, note: note, velocity: 1));
          apply(MidiNoteOn(channel: 0, note: note, velocity: 1));
          apply(MidiPolyPressure(channel: 0, note: note, pressure: 1));
        }
        for (var p = 0; p < 20; p++) {
          cc(101, 0);
          cc(100, p);
          cc(6, 1);
        }
        final channel = build(seq: 11).channelJournals.single;
        expect(channel.toBytes().length, lessThanOrEqualTo(1023));
        expect(channel.chapterM!.logs, isEmpty);
        expect(channel.chapterC!.logs.length, lessThan(126));
        expect(issues.single, startsWith('queueOverflow: The journal of'));
      });
    });
  });
}
