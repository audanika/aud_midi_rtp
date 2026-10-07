// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpJournalRepair', () {
    late MidiRtpStreamState model;
    late MidiRtpJournalRepair repair;
    late List<String> issues;

    setUp(() {
      model = MidiRtpStreamState();
      issues = [];
      repair = MidiRtpJournalRepair(
        model: model,
        onIssue: (kind, cause) => issues.add('${kind.name}: $cause'),
      );
    });

    MidiControlChange cc(int controller, int value, {int channel = 0}) =>
        MidiControlChange(
          channel: channel,
          controller: controller,
          value: value,
        );

    List<MidiMessage> run({
      MidiRtpSystemJournal? system,
      List<MidiRtpChannelJournal> channels = const [],
      bool s = true,
      bool single = false,
      bool covered = true,
      int checkpoint = 5,
    }) => repair.repair(
      MidiRtpJournal(
        s: s,
        checkpoint: checkpoint,
        systemJournal: system,
        channelJournals: channels,
      ),
      seq: 10,
      checkpoint: checkpoint,
      singleLoss: single,
      covered: covered,
    );

    List<MidiMessage> channel0(
      MidiRtpChannelJournal journal, {
      bool single = false,
    }) => run(channels: [journal], s: journal.s, single: single);

    group('repair(journal, seq, checkpoint, singleLoss, covered)', () {
      test('skips a safe journal after a single loss', () {
        expect(
          run(
            single: true,
            channels: [
              const MidiRtpChannelJournal(
                channel: 0,
                chapterP: MidiRtpChapterP(program: 1),
              ),
            ],
          ),
          isEmpty,
        );
      });

      test('skips safe channel and system journals after a single loss', () {
        expect(
          run(
            s: false,
            single: true,
            system: const MidiRtpSystemJournal(
              chapterD: MidiRtpChapterD(songSelect: (s: true, value: 1)),
            ),
            channels: [
              const MidiRtpChannelJournal(
                channel: 0,
                chapterP: MidiRtpChapterP(program: 1),
              ),
            ],
          ),
          isEmpty,
        );
      });

      test('applies every repair to the model', () {
        run(
          channels: [
            const MidiRtpChannelJournal(
              channel: 1,
              chapterP: MidiRtpChapterP(program: 1),
            ),
          ],
        );
        expect(model.channels[1].program!.program, 1);
        expect(model.channels[1].program!.seq, 10);
        expect(repair.model, same(model));
        expect(repair.onIssue, isNotNull);
      });
    });

    group('Chapter P', () {
      test('replays a lost program change with its bank', () {
        model.apply(cc(32, 9));
        expect(
          channel0(
            const MidiRtpChannelJournal(
              channel: 0,
              chapterP: MidiRtpChapterP(
                program: 5,
                b: true,
                bankMsb: 2,
                bankLsb: 3,
              ),
            ),
          ),
          equals([
            cc(0, 2),
            cc(32, 3),
            const MidiProgramChange(channel: 0, program: 5),
          ]),
        );
      });

      test('keeps bank registers that already match', () {
        model
          ..apply(cc(0, 2))
          ..apply(cc(32, 3));
        expect(
          channel0(
            const MidiRtpChannelJournal(
              channel: 0,
              chapterP: MidiRtpChapterP(
                program: 5,
                b: true,
                bankMsb: 2,
                bankLsb: 3,
              ),
            ),
          ),
          equals([const MidiProgramChange(channel: 0, program: 5)]),
        );
        model.apply(cc(0, 4));
        expect(
          channel0(
            const MidiRtpChannelJournal(
              channel: 0,
              chapterP: MidiRtpChapterP(program: 6, b: true, bankMsb: 4),
            ),
          ),
          equals([const MidiProgramChange(channel: 0, program: 6)]),
        );
      });

      test('repairs nothing for the same program', () {
        model
          ..apply(cc(0, 2))
          ..apply(const MidiProgramChange(channel: 0, program: 5));
        for (final chapter in [
          const MidiRtpChapterP(program: 5),
          const MidiRtpChapterP(program: 5, b: true, bankMsb: 2),
        ]) {
          expect(
            channel0(MidiRtpChannelJournal(channel: 0, chapterP: chapter)),
            isEmpty,
          );
        }
        expect(
          channel0(
            const MidiRtpChannelJournal(
              channel: 0,
              chapterP: MidiRtpChapterP(program: 5, b: true, bankMsb: 7),
            ),
          ),
          equals([cc(0, 7), const MidiProgramChange(channel: 0, program: 5)]),
        );
      });
    });

    group('Chapter C', () {
      MidiRtpControllerLog log(
        int number,
        MidiRtpControllerTool tool,
        int value, {
        bool s = true,
      }) =>
          MidiRtpControllerLog(s: s, number: number, tool: tool, value: value);
      const count = MidiRtpControllerTool.count;
      const value = MidiRtpControllerTool.value;
      const toggle = MidiRtpControllerTool.toggle;

      List<MidiMessage> chapterC(
        List<MidiRtpControllerLog> logs, {
        bool single = false,
        bool s = true,
      }) => channel0(
        MidiRtpChannelJournal(
          channel: 0,
          s: s,
          chapterC: MidiRtpChapterC(s: s, logs: logs),
        ),
        single: single,
      );

      test('replays lost values', () {
        model.apply(cc(7, 100));
        expect(
          chapterC([log(7, value, 100), log(10, value, 20)]),
          equals([cc(10, 20)]),
        );
      });

      test('skips safe logs after a single loss', () {
        expect(
          chapterC(
            [log(7, value, 1), log(10, value, 20, s: false)],
            single: true,
            s: false,
          ),
          equals([cc(10, 20)]),
        );
      });

      test('replays lost commands by their count', () {
        model.apply(cc(123, 0));
        expect(
          chapterC([
            log(123, count, 1),
            log(123, value, 0),
            log(120, count, 2),
          ]),
          equals([cc(120, 0)]),
        );
        expect(model.channels[0].controllerCount(120), 2);
      });

      test('ignores older commands of the enhanced encoding', () {
        model
          ..apply(cc(16, 1))
          ..apply(cc(16, 2))
          ..apply(cc(16, 3));
        expect(
          chapterC([
            log(16, count, 2),
            log(16, value, 2),
            log(16, count, 3),
            log(16, value, 3),
            log(16, count, 4),
            log(16, value, 4),
          ]),
          equals([cc(16, 4)]),
        );
        expect(model.channels[0].controllerCount(16), 4);
      });

      test('uses default values for count-only logs', () {
        expect(
          chapterC([
            for (final n in [7, 8, 10, 70, 11, 122, 1]) log(n, count, 1),
          ]),
          equals([
            cc(7, 100),
            cc(8, 64),
            cc(10, 64),
            cc(70, 64),
            cc(11, 127),
            cc(122, 127),
            cc(1, 0),
          ]),
        );
      });

      test('damps notes for an even number of lost toggles', () {
        model.apply(cc(64, 127));
        expect(
          chapterC([
            log(64, count, 3),
            log(64, value, 127),
            log(64, toggle, 3),
          ]),
          equals([cc(64, 0), cc(64, 127)]),
        );
        expect(model.channels[0].controller(64)!.toggles, 3);
        expect(model.channels[0].controllerToggles(64), 3);
      });

      test('repairs toggle-only logs', () {
        model.apply(cc(66, 127));
        expect(chapterC([log(66, toggle, 1)]), isEmpty);
        expect(chapterC([log(66, toggle, 2)]), equals([cc(66, 0)]));
        expect(chapterC([log(67, toggle, 1)]), equals([cc(67, 0)]));
        expect(chapterC([log(67, toggle, 4)]), equals([cc(67, 0)]));
      });

      test('replays a value after a lost Reset All Controllers', () {
        model.apply(cc(1, 50));
        expect(
          chapterC([log(121, count, 1), log(121, value, 0), log(1, value, 50)]),
          equals([cc(121, 0), cc(1, 50)]),
        );
      });

      test('keeps a value that preceded a received Reset All Controllers', () {
        model
          ..apply(cc(1, 50))
          ..apply(cc(121, 0));
        expect(
          chapterC([log(1, value, 50), log(121, count, 1), log(121, value, 0)]),
          isEmpty,
        );
        expect(chapterC([log(1, value, 50)]), equals([cc(1, 50)]));
      });

      test('closes a stale selection before general-purpose data entry', () {
        model
          ..apply(cc(101, 0))
          ..apply(cc(100, 0));
        expect(
          chapterC([log(6, value, 9)]),
          equals([cc(101, 127), cc(100, 127), cc(6, 9)]),
        );
        expect(model.channels[0].controller(6)!.value, 9);
      });
    });

    group('Chapter M', () {
      List<MidiMessage> chapterM(
        MidiRtpChapterM chapter, {
        bool single = false,
      }) => channel0(
        MidiRtpChannelJournal(channel: 0, s: chapter.s, chapterM: chapter),
        single: single,
      );

      test('replays a lost parameter transaction', () {
        expect(
          chapterM(
            MidiRtpChapterM(
              e: true,
              logs: [
                const MidiRtpParameterLog(
                  number: 130,
                  entryMsb: (value: 1, x: false),
                  entryLsb: (value: 2, x: false),
                  aButton: (count: 2, x: false),
                ),
              ],
            ),
          ),
          equals([
            cc(101, 1),
            cc(100, 2),
            cc(6, 1),
            cc(38, 2),
            cc(96, 0),
            cc(96, 0),
          ]),
        );
        expect(model.channels[0].parameterSystem.selection, (
          nrpn: false,
          number: 130,
          pending: false,
        ));
      });

      test('replays only lost increments and selects the current one', () {
        model
          ..apply(cc(99, 0))
          ..apply(cc(98, 1))
          ..apply(cc(6, 5))
          ..apply(cc(96, 0))
          ..apply(cc(101, 0))
          ..apply(cc(100, 9));
        expect(
          chapterM(
            MidiRtpChapterM(
              e: true,
              logs: [
                const MidiRtpParameterLog(
                  nrpn: true,
                  number: 1,
                  aButton: (count: -1, x: false),
                ),
              ],
            ),
          ),
          equals([cc(99, 0), cc(98, 1), cc(97, 0), cc(97, 0)]),
        );
      });

      test('derives values the log leaves out from the model', () {
        model
          ..apply(cc(101, 0))
          ..apply(cc(100, 1))
          ..apply(cc(6, 5))
          ..apply(cc(38, 6));
        for (final log in [
          const MidiRtpParameterLog(number: 1),
          const MidiRtpParameterLog(number: 1, entryMsb: (value: 5, x: false)),
          const MidiRtpParameterLog(number: 1, v: false),
        ]) {
          expect(chapterM(MidiRtpChapterM(e: true, logs: [log])), [
            if (log.entryMsb != null) ...[cc(101, 0), cc(100, 1), cc(6, 5)],
          ]);
          model
            ..apply(cc(101, 0))
            ..apply(cc(100, 1))
            ..apply(cc(6, 5))
            ..apply(cc(38, 6));
        }
        expect(
          chapterM(
            MidiRtpChapterM(
              e: true,
              logs: [
                const MidiRtpParameterLog(
                  number: 1,
                  entryLsb: (value: 7, x: false),
                ),
              ],
            ),
          ),
          equals([cc(101, 0), cc(100, 1), cc(6, 5), cc(38, 7)]),
        );
      });

      test('skips safe logs after a single loss', () {
        expect(
          chapterM(
            MidiRtpChapterM(
              s: false,
              logs: [
                const MidiRtpParameterLog(
                  number: 1,
                  entryMsb: (value: 5, x: false),
                ),
              ],
            ),
            single: true,
          ),
          isEmpty,
        );
      });

      test('restores a pending MSB', () {
        final chapter = MidiRtpChapterM(pending: (value: 3, nrpn: true));
        expect(chapterM(chapter), equals([cc(99, 3)]));
        expect(chapterM(chapter), isEmpty);
        model.apply(cc(101, 3));
        expect(chapterM(chapter), equals([cc(99, 3)]));
        model.apply(cc(99, 4));
        expect(chapterM(chapter), equals([cc(99, 3)]));
        model
          ..apply(cc(99, 3))
          ..apply(cc(98, 0));
        expect(chapterM(chapter), equals([cc(99, 3)]));
      });

      test('closes a selection the stream closed', () {
        model
          ..apply(cc(101, 0))
          ..apply(cc(100, 0));
        expect(
          chapterM(MidiRtpChapterM()),
          equals([cc(101, 127), cc(100, 127)]),
        );
        expect(chapterM(MidiRtpChapterM()), isEmpty);
        expect(chapterM(MidiRtpChapterM(e: true)), isEmpty);
      });

      test('selects the parameter of the most recent log', () {
        final chapter = MidiRtpChapterM(
          e: true,
          logs: [const MidiRtpParameterLog(nrpn: true, number: 7)],
        );
        expect(chapterM(chapter), equals([cc(99, 0), cc(98, 7)]));
        expect(chapterM(chapter), isEmpty);
        model.apply(cc(99, 0));
        expect(chapterM(chapter), equals([cc(99, 0), cc(98, 7)]));
        model
          ..apply(cc(101, 0))
          ..apply(cc(100, 7));
        expect(chapterM(chapter), equals([cc(99, 0), cc(98, 7)]));
        model
          ..apply(cc(99, 0))
          ..apply(cc(98, 8));
        expect(chapterM(chapter), equals([cc(99, 0), cc(98, 7)]));
      });
    });

    group('Chapters W, T and A', () {
      test('replay lost values', () {
        model
          ..apply(const MidiPitchBend(channel: 0, value: 5))
          ..apply(const MidiPolyPressure(channel: 0, note: 1, pressure: 2));
        expect(
          channel0(
            MidiRtpChannelJournal(
              channel: 0,
              chapterW: const MidiRtpChapterW(value: 6),
              chapterT: const MidiRtpChapterT(pressure: 7),
              chapterA: MidiRtpChapterA(
                logs: [
                  const MidiRtpPressureLog(note: 1, pressure: 2),
                  const MidiRtpPressureLog(note: 3, pressure: 4),
                ],
              ),
            ),
          ),
          equals([
            const MidiPitchBend(channel: 0, value: 6),
            const MidiChannelPressure(channel: 0, pressure: 7),
            const MidiPolyPressure(channel: 0, note: 3, pressure: 4),
          ]),
        );
        expect(
          channel0(
            MidiRtpChannelJournal(
              channel: 0,
              chapterW: const MidiRtpChapterW(value: 6),
              chapterT: const MidiRtpChapterT(pressure: 7),
              chapterA: MidiRtpChapterA(
                logs: [const MidiRtpPressureLog(note: 3, pressure: 4)],
              ),
            ),
          ),
          isEmpty,
        );
      });

      test('skip safe chapters and logs after a single loss', () {
        expect(
          channel0(
            MidiRtpChannelJournal(
              channel: 0,
              s: false,
              chapterW: const MidiRtpChapterW(value: 6),
              chapterT: const MidiRtpChapterT(pressure: 7),
              chapterA: MidiRtpChapterA(
                s: false,
                logs: [
                  const MidiRtpPressureLog(note: 1, pressure: 2),
                  const MidiRtpPressureLog(s: false, note: 3, pressure: 4),
                ],
              ),
            ),
            single: true,
          ),
          equals([const MidiPolyPressure(channel: 0, note: 3, pressure: 4)]),
        );
      });
    });

    group('Chapters N and E', () {
      test('end notes of the NoteOff bitfield', () {
        model
          ..apply(const MidiNoteOn(channel: 0, note: 60, velocity: 1))
          ..apply(const MidiNoteOn(channel: 0, note: 60, velocity: 1))
          ..apply(const MidiNoteOn(channel: 0, note: 61, velocity: 1))
          ..apply(const MidiNoteOn(channel: 0, note: 62, velocity: 1))
          ..apply(const MidiNoteOn(channel: 0, note: 62, velocity: 1));
        expect(
          channel0(
            MidiRtpChannelJournal(
              channel: 0,
              chapterN: MidiRtpChapterN(offNotes: [60, 61, 62, 63]),
              chapterE: MidiRtpChapterE(
                logs: [
                  const MidiRtpNoteExtraLog(note: 61, v: true, value: 30),
                  const MidiRtpNoteExtraLog(note: 62, v: false, value: 1),
                ],
              ),
            ),
          ),
          equals([
            const MidiNoteOff(channel: 0, note: 60),
            const MidiNoteOff(channel: 0, note: 60),
            const MidiNoteOff(channel: 0, note: 61, velocity: 30),
            const MidiNoteOff(channel: 0, note: 62),
          ]),
        );
        expect(model.channels[0].note(62)!.count, 1);
        expect(model.hasSoundingNotes, isFalse);
      });

      test('skip a safe NoteOff bitfield after a single loss', () {
        model.apply(const MidiNoteOn(channel: 0, note: 60, velocity: 1));
        expect(
          channel0(
            MidiRtpChannelJournal(
              channel: 0,
              s: false,
              chapterN: MidiRtpChapterN(
                logs: [
                  const MidiRtpNoteLog(note: 61, velocity: 2),
                  const MidiRtpNoteLog(s: false, note: 62, velocity: 3),
                ],
                offNotes: [60],
              ),
            ),
            single: true,
          ),
          equals([const MidiNoteOn(channel: 0, note: 62, velocity: 3)]),
        );
      });

      test('play lost NoteOns with the Y bit and skip the others', () {
        expect(
          channel0(
            MidiRtpChannelJournal(
              channel: 0,
              chapterN: MidiRtpChapterN(
                logs: [
                  const MidiRtpNoteLog(note: 60, velocity: 2),
                  const MidiRtpNoteLog(note: 61, y: false, velocity: 3),
                ],
              ),
              chapterE: MidiRtpChapterE(
                logs: [const MidiRtpNoteExtraLog(note: 60, v: false, value: 2)],
              ),
            ),
          ),
          equals([const MidiNoteOn(channel: 0, note: 60, velocity: 2)]),
        );
        expect(model.channels[0].note(60)!.count, 2);
        expect(model.channels[0].note(61)!.on, isTrue);
      });

      test('retrigger notes whose NoteOff was lost', () {
        model
          ..apply(const MidiNoteOn(channel: 0, note: 60, velocity: 2), seq: 7)
          ..apply(const MidiNoteOn(channel: 0, note: 61, velocity: 2), seq: 3)
          ..apply(const MidiNoteOn(channel: 0, note: 62, velocity: 2), seq: 7);
        expect(
          channel0(
            MidiRtpChannelJournal(
              channel: 0,
              chapterN: MidiRtpChapterN(
                logs: [
                  const MidiRtpNoteLog(note: 60, velocity: 2),
                  const MidiRtpNoteLog(note: 61, velocity: 2),
                  const MidiRtpNoteLog(note: 62, velocity: 4),
                ],
              ),
            ),
          ),
          equals([
            const MidiNoteOff(channel: 0, note: 61),
            const MidiNoteOn(channel: 0, note: 61, velocity: 2),
            const MidiNoteOff(channel: 0, note: 62),
            const MidiNoteOn(channel: 0, note: 62, velocity: 4),
          ]),
        );
      });
    });

    group('uncovered losses', () {
      test('end the notes the journal does not confirm', () {
        model
          ..apply(const MidiNoteOn(channel: 0, note: 60, velocity: 1))
          ..apply(const MidiNoteOn(channel: 0, note: 61, velocity: 1), seq: 7)
          ..apply(const MidiNoteOn(channel: 3, note: 62, velocity: 1));
        expect(
          run(
            covered: false,
            channels: [
              MidiRtpChannelJournal(
                channel: 0,
                chapterN: MidiRtpChapterN(
                  logs: [const MidiRtpNoteLog(note: 61, velocity: 1)],
                ),
              ),
            ],
          ),
          equals([
            const MidiNoteOff(channel: 0, note: 60),
            const MidiNoteOff(channel: 3, note: 62),
          ]),
        );
      });
    });

    group('silence(seq)', () {
      test('ends notes and releases sustaining pedals', () {
        model
          ..apply(const MidiNoteOn(channel: 1, note: 60, velocity: 1))
          ..apply(const MidiNoteOff(channel: 1, note: 61))
          ..apply(cc(64, 127, channel: 1))
          ..apply(cc(66, 10, channel: 1))
          ..apply(cc(69, 100, channel: 2));
        expect(
          repair.silence(seq: 3),
          equals([
            const MidiNoteOff(channel: 1, note: 60),
            cc(64, 0, channel: 1),
            cc(69, 0, channel: 2),
          ]),
        );
        expect(repair.silence(seq: 3), isEmpty);
      });
    });

    group('Chapter D', () {
      List<MidiMessage> chapterD(
        MidiRtpChapterD chapter, {
        bool single = false,
      }) => run(
        system: MidiRtpSystemJournal(s: chapter.s, chapterD: chapter),
        s: chapter.s,
        single: single,
      );

      test('replays Reset, Tune Request and Song Select', () {
        expect(
          chapterD(
            const MidiRtpChapterD(
              reset: (s: true, value: 3),
              tuneRequest: (s: true, value: 5),
              songSelect: (s: true, value: 7),
            ),
          ),
          equals([
            const MidiSystemReset(),
            const MidiTuneRequest(),
            const MidiSongSelect(song: 7),
          ]),
        );
        expect(model.system.resetCount, 3);
        expect(model.system.tuneRequestCount, 5);
        expect(
          chapterD(
            const MidiRtpChapterD(
              reset: (s: true, value: 3),
              tuneRequest: (s: true, value: 5),
              songSelect: (s: true, value: 7),
            ),
          ),
          isEmpty,
        );
      });

      test('skips safe logs after a single loss', () {
        expect(
          chapterD(
            const MidiRtpChapterD(
              s: false,
              reset: (s: true, value: 3),
              tuneRequest: (s: true, value: 5),
              songSelect: (s: false, value: 7),
            ),
            single: true,
          ),
          equals([const MidiSongSelect(song: 7)]),
        );
        expect(
          chapterD(
            const MidiRtpChapterD(songSelect: (s: false, value: 8)),
            single: true,
          ),
          isEmpty,
        );
      });

      test('replays undefined commands', () {
        expect(
          chapterD(
            MidiRtpChapterD(
              f4: MidiRtpUndefinedCommonLog(dsz: 0, count: 1),
              f5: MidiRtpUndefinedCommonLog(dsz: 2, value: [1, 2]),
              f9: MidiRtpUndefinedRealTimeLog(count: 2),
              fd: MidiRtpUndefinedRealTimeLog(),
            ),
          ),
          equals([
            MidiRtpJournalRepair.undefinedMessage(0xF4, const []),
            MidiRtpJournalRepair.undefinedMessage(0xF5, const [1, 2]),
            MidiRtpJournalRepair.undefinedMessage(0xF9, const []),
          ]),
        );
        expect(model.system.undefinedCount(0xF4), 1);
        expect(model.system.undefinedCount(0xF9), 2);
        expect(
          chapterD(
            MidiRtpChapterD(
              f4: MidiRtpUndefinedCommonLog(dsz: 0, count: 1),
              f5: MidiRtpUndefinedCommonLog(dsz: 2, value: [1, 2]),
              f9: MidiRtpUndefinedRealTimeLog(count: 2),
            ),
          ),
          isEmpty,
        );
        expect(
          chapterD(
            MidiRtpChapterD(
              f5: MidiRtpUndefinedCommonLog(dsz: 3, value: [1, 2, 3]),
            ),
          ),
          isEmpty,
        );
        expect(issues.single, startsWith('untranslatable: Undefined command'));
        expect(
          chapterD(
            MidiRtpChapterD(
              s: false,
              f4: MidiRtpUndefinedCommonLog(dsz: 0, count: 5),
              f9: MidiRtpUndefinedRealTimeLog(count: 5),
            ),
            single: true,
          ),
          isEmpty,
        );
      });

      test('code the data of undefined commands as UMP', () {
        expect(
          MidiRtpJournalRepair.undefinedMessage(0xF4, const [1]).umps.single,
          Ump([0x10F40100]),
        );
        expect(
          MidiRtpJournalRepair.undefinedMessage(0xF5, const [1, 2]).umps.single,
          Ump([0x10F50102]),
        );
      });
    });

    group('Chapter V', () {
      test('replays Active Sense', () {
        const system = MidiRtpSystemJournal(
          chapterV: MidiRtpChapterV(count: 4),
        );
        expect(run(system: system), equals([const MidiActiveSensing()]));
        expect(model.system.activeSenseCount, 4);
        expect(run(system: system), isEmpty);
      });
    });

    group('Chapter Q', () {
      List<MidiMessage> chapterQ(MidiRtpChapterQ chapter) =>
          run(system: MidiRtpSystemJournal(chapterQ: chapter));

      test('starts the sequencer at the start of the song', () {
        expect(
          chapterQ(const MidiRtpChapterQ(n: true)),
          equals([const MidiStart()]),
        );
        expect(chapterQ(const MidiRtpChapterQ(n: true)), isEmpty);
      });

      test('locates and continues', () {
        model.apply(const MidiStart());
        expect(
          chapterQ(const MidiRtpChapterQ(n: true, position: 24)),
          equals([
            const MidiStop(),
            const MidiSongPositionPointer(position: 4),
            const MidiContinue(),
          ]),
        );
        expect(
          chapterQ(const MidiRtpChapterQ(position: 12)),
          equals([
            const MidiStop(),
            const MidiSongPositionPointer(position: 2),
          ]),
        );
      });

      test('replays clocks after the downbeat', () {
        expect(
          chapterQ(const MidiRtpChapterQ(n: true, d: true, position: 8)),
          equals([
            const MidiSongPositionPointer(position: 1),
            const MidiContinue(),
            const MidiTimingClock(),
            const MidiTimingClock(),
            const MidiTimingClock(),
          ]),
        );
        expect(model.system.sequencer.position, 8);
        expect(
          chapterQ(const MidiRtpChapterQ(d: true, position: 13)),
          equals([
            const MidiStop(),
            const MidiSongPositionPointer(position: 2),
            const MidiContinue(),
            const MidiTimingClock(),
            const MidiTimingClock(),
            const MidiStop(),
          ]),
        );
      });
    });

    group('Chapter F', () {
      const code = MidiRtpTimeCode(hours: 1, minutes: 2);
      final fullFrame = MidiSysEx([0x7F, 0x7F, 0x01, 0x01, 1, 2, 0, 0]);

      List<MidiMessage> chapterF(MidiRtpChapterF chapter) =>
          run(system: MidiRtpSystemJournal(chapterF: chapter));

      test('relocates with a Full Frame message', () {
        expect(
          chapterF(MidiRtpChapterF(complete: code.toField(nibbles: false))),
          equals([fullFrame]),
        );
        expect(model.system.sysExCount, 0);
        expect(
          chapterF(MidiRtpChapterF(complete: code.toField(nibbles: false))),
          isEmpty,
        );
        expect(
          chapterF(
            MidiRtpChapterF(complete: code.toField(nibbles: true), q: true),
          ),
          isEmpty,
        );
      });

      test('replays the partial frame forward and in reverse', () {
        expect(
          chapterF(
            MidiRtpChapterF(
              complete: code.toField(nibbles: false),
              point: 1,
              partial: 0x12000000,
            ),
          ),
          equals([
            fullFrame,
            const MidiTimeCodeQuarterFrame(piece: 0, value: 1),
            const MidiTimeCodeQuarterFrame(piece: 1, value: 2),
          ]),
        );
        expect(
          chapterF(
            MidiRtpChapterF(
              complete: code.toField(nibbles: false),
              point: 1,
              partial: 0x12000000,
            ),
          ),
          isEmpty,
        );
        expect(
          chapterF(
            MidiRtpChapterF(
              complete: code.toField(nibbles: false),
              d: true,
              point: 6,
              partial: 0x00000034,
            ),
          ),
          equals([
            fullFrame,
            const MidiTimeCodeQuarterFrame(piece: 7, value: 4),
            const MidiTimeCodeQuarterFrame(piece: 6, value: 3),
          ]),
        );
      });

      test('compares point, direction and nibbles of the partial frame', () {
        model.system.applySysEx(MidiRtpSysExKind.complete, fullFrame.data);
        model.apply(const MidiTimeCodeQuarterFrame(piece: 0, value: 1));
        for (final chapter in [
          MidiRtpChapterF(
            complete: code.toField(nibbles: false),
            point: 0,
            partial: 0x20000000,
          ),
          MidiRtpChapterF(
            complete: code.toField(nibbles: false),
            point: 1,
            partial: 0x10000000,
          ),
          MidiRtpChapterF(
            complete: code.toField(nibbles: false),
            d: true,
            point: 0,
            partial: 0x10000000,
          ),
          MidiRtpChapterF(complete: code.toField(nibbles: false)),
        ]) {
          expect(chapterF(chapter).first, fullFrame);
          model.apply(const MidiTimeCodeQuarterFrame(piece: 0, value: 1));
        }
      });

      test('replays a partial frame without a complete one', () {
        expect(
          chapterF(const MidiRtpChapterF(point: 0, partial: 0x50000000)),
          equals([const MidiTimeCodeQuarterFrame(piece: 0, value: 5)]),
        );
        expect(chapterF(const MidiRtpChapterF()), isEmpty);
      });
    });

    group('Chapter X', () {
      List<MidiMessage> chapterX(
        List<MidiRtpSysExLog> logs, {
        bool single = false,
      }) {
        final chapter = MidiRtpChapterX(logs: logs);
        return run(
          system: MidiRtpSystemJournal(s: chapter.s, chapterX: chapter),
          s: chapter.s,
          single: single,
        );
      }

      MidiRtpSysExLog log(
        int? count,
        List<int>? data,
        MidiRtpSysExStatus status, {
        int? first,
        bool s = true,
      }) => MidiRtpSysExLog(
        s: s,
        count: count,
        first: first,
        data: data,
        status: status,
      );
      const finished = MidiRtpSysExStatus.finished;

      test('replays lost commands by their COUNT', () {
        model.apply(MidiSysEx([1]));
        expect(
          chapterX([
            log(1, [1], finished),
            log(3, [3], MidiRtpSysExStatus.droppedF7),
          ]),
          equals([
            MidiSysEx([3]),
          ]),
        );
        expect(model.system.sysExCount, 3);
        expect(model.system.sysEx.last.status, MidiRtpSysExStatus.droppedF7);
      });

      test('replays a lost Reset State command before the others', () {
        model.apply(const MidiProgramChange(channel: 0, program: 1));
        expect(
          run(
            system: MidiRtpSystemJournal(
              chapterD: const MidiRtpChapterD(songSelect: (s: true, value: 2)),
              chapterX: MidiRtpChapterX(
                logs: [
                  log(1, [0x7E, 0x7F, 0x09, 0x01], finished),
                ],
              ),
            ),
          ),
          equals([
            MidiSysEx([0x7E, 0x7F, 0x09, 0x01]),
            const MidiSongSelect(song: 2),
          ]),
        );
        expect(model.channels[0].program, isNull);
        expect(model.system.songSelect!.value, 2);
      });

      test('starts, continues and completes segmented commands', () {
        expect(
          chapterX([
            log(1, [1, 2], MidiRtpSysExStatus.unfinished),
          ]),
          isEmpty,
        );
        expect(model.system.unfinishedSysEx!.data, equals([1, 2]));
        expect(
          chapterX([
            log(1, [3, 4], MidiRtpSysExStatus.unfinished, first: 1),
          ]),
          isEmpty,
        );
        expect(model.system.unfinishedSysEx!.data, equals([1, 2, 4]));
        expect(
          chapterX([log(1, null, finished, first: 3)]),
          equals([
            MidiSysEx([1, 2, 4]),
          ]),
        );
        expect(model.system.unfinishedSysEx, isNull);
      });

      test('cancels an unfinished command', () {
        model.applySysEx(MidiRtpSysExKind.first, [1]);
        expect(chapterX([log(1, null, MidiRtpSysExStatus.cancelled)]), isEmpty);
        expect(model.system.sysEx.single.status, MidiRtpSysExStatus.cancelled);
        expect(chapterX([log(2, null, MidiRtpSysExStatus.cancelled)]), isEmpty);
        expect(model.system.sysExCount, 2);
      });

      test('reports a lost start it cannot repair', () {
        expect(
          chapterX([
            log(1, [5], finished, first: 4),
          ]),
          isEmpty,
        );
        expect(issues.single, startsWith('sysExIncomplete:'));
        expect(model.system.sysExCount, 1);
      });

      test('ignores seen commands and safe logs', () {
        model.apply(MidiSysEx([1]));
        expect(
          chapterX([
            log(1, [1], finished),
          ]),
          isEmpty,
        );
        expect(
          chapterX([
            log(1, [1], finished, s: false),
            log(2, [2], finished, s: false),
          ], single: true),
          equals([
            MidiSysEx([2]),
          ]),
        );
      });

      test('compares data when a log has no COUNT', () {
        model.apply(MidiSysEx([1]));
        expect(
          chapterX([
            log(null, [1], finished),
          ]),
          isEmpty,
        );
        expect(
          chapterX([
            log(null, [2], finished),
          ]),
          equals([
            MidiSysEx([2]),
          ]),
        );
        expect(
          chapterX([
            log(null, [3], MidiRtpSysExStatus.unfinished),
          ]),
          isEmpty,
        );
        expect(
          chapterX([
            log(null, [3], finished, first: 1),
          ]),
          isEmpty,
        );
      });
    });
  });
}
