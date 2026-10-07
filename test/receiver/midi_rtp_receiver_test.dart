// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:math';

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpReceiver', () {
    late List<String> issues;
    late MidiRtpReceiver receiver;

    MidiRtpReceiver create({
      MidiRtpSessionConfig config = MidiRtpSessionConfig.appleMidi,
      int maxSysExLength = 1 << 20,
    }) => MidiRtpReceiver(
      config: config,
      maxSysExLength: maxSysExLength,
      onIssue: (kind, cause) => issues.add('${kind.name}: $cause'),
    );

    MidiRtpPacket packet(
      int seq,
      List<MidiRtpCommand> commands, {
      MidiRtpJournal? journal,
      int timestamp = 0,
      int ssrc = 1,
      int payloadType = 97,
    }) => MidiRtpPacket(
      header: MidiRtpHeader(
        payloadType: payloadType,
        sequenceNumber: seq,
        timestamp: timestamp,
        ssrc: ssrc,
      ),
      payload: MidiRtpPayload(
        commands: commands,
        journal: journal ?? MidiRtpJournal(checkpoint: seq),
      ),
    );

    MidiRtpMessageCommand command(MidiMessage message, [int deltaTime = 0]) =>
        MidiRtpMessageCommand(deltaTime: deltaTime, message: message);

    setUp(() {
      issues = [];
      receiver = create();
    });

    group('receive(bytes)', () {
      test('decodes commands with their times', () {
        final messages = receiver.receive(
          packet(5, [
            command(const MidiNoteOn(channel: 0, note: 60, velocity: 1)),
            command(const MidiTimingClock(), 3),
          ], timestamp: 10).toBytes(),
        );
        expect(
          messages,
          equals([
            (
              message: const MidiNoteOn(channel: 0, note: 60, velocity: 1),
              time: const MidiTime(1000),
            ),
            (message: const MidiTimingClock(), time: const MidiTime(1300)),
          ]),
        );
        expect(receiver.model.channels[0].note(60)!.seq, 5);
        expect(receiver.ssrc, 1);
        expect(receiver.feedbackSequenceNumber, 5);
        expect(receiver.highestSequenceNumber, 5);
        expect(receiver.packetsReceived, 1);
      });

      test('reports malformed packets', () {
        expect(receiver.receive([0x80]), isEmpty);
        expect(receiver.packetsDiscarded, 1);
        expect(issues.single, startsWith('invalidData: Malformed packet'));
      });
    });

    group('receivePacket(packet)', () {
      test('ignores foreign payload types', () {
        expect(receiver.receivePacket(packet(1, [], payloadType: 96)), isEmpty);
        expect(issues.single, 'invalidData: Payload type 96 is not 97');
        expect(receiver.packetsDiscarded, 1);
      });

      test('ignores duplicate and late packets', () {
        receiver.receivePacket(packet(5, []));
        expect(
          receiver.receivePacket(packet(5, [command(const MidiStart())])),
          isEmpty,
        );
        expect(
          receiver.receivePacket(packet(4, [command(const MidiStart())])),
          isEmpty,
        );
        expect(receiver.packetsDiscarded, 2);
        expect(issues, isEmpty);
      });

      test('repairs from the journal after a loss', () {
        receiver.receivePacket(packet(5, []));
        final messages = receiver.receivePacket(
          packet(
            8,
            [command(const MidiStart())],
            timestamp: 20,
            journal: MidiRtpJournal(
              checkpoint: 6,
              channelJournals: [
                const MidiRtpChannelJournal(
                  channel: 2,
                  chapterP: MidiRtpChapterP(program: 3),
                ),
              ],
            ),
          ),
        );
        expect(
          messages,
          equals([
            (
              message: const MidiProgramChange(channel: 2, program: 3),
              time: const MidiTime(2000),
            ),
            (message: const MidiStart(), time: const MidiTime(2000)),
          ]),
        );
        expect(receiver.packetsLost, 2);
        expect(receiver.packetsRecovered, 2);
        expect(receiver.journalRepairs, 1);
        expect(
          issues.single,
          'networkLoss: Lost 2 packet(s) before 8, recovered from the journal',
        );
        expect(
          receiver.lossStats,
          const MidiNetworkLossStats(
            packetsReceived: 2,
            packetsLost: 2,
            packetsRecovered: 2,
            journalRepairs: 1,
          ),
        );
      });

      test('treats the first packet like the end of a loss', () {
        final messages = receiver.receivePacket(
          packet(
            9,
            [],
            journal: MidiRtpJournal(
              checkpoint: 2,
              channelJournals: [
                const MidiRtpChannelJournal(
                  channel: 0,
                  chapterW: MidiRtpChapterW(value: 9),
                ),
              ],
            ),
          ),
        );
        expect(
          messages.single.message,
          const MidiPitchBend(channel: 0, value: 9),
        );
        expect(issues, isEmpty);
      });

      test('protects against uncovered losses', () {
        receiver.receivePacket(
          packet(5, [
            command(const MidiNoteOn(channel: 0, note: 60, velocity: 1)),
          ]),
        );
        final messages = receiver.receivePacket(
          packet(9, [], journal: MidiRtpJournal(checkpoint: 8)),
        );
        expect(
          messages.single.message,
          const MidiNoteOff(channel: 0, note: 60),
        );
        expect(receiver.packetsRecovered, 0);
        expect(issues.single, contains('not covered by the journal'));
      });

      test('silences notes after a loss without journal', () {
        receiver.receivePacket(
          packet(5, [
            command(const MidiNoteOn(channel: 0, note: 60, velocity: 1)),
          ]),
        );
        final noJournal = MidiRtpPacket(
          header: MidiRtpHeader(
            payloadType: 97,
            sequenceNumber: 7,
            timestamp: 0,
            ssrc: 1,
          ),
          payload: MidiRtpPayload(),
        );
        expect(
          receiver.receivePacket(noJournal).single.message,
          const MidiNoteOff(channel: 0, note: 60),
        );
        expect(issues.single, contains('without a journal'));
        final first = create()..receivePacket(noJournal.copyWith());
        expect(first.packetsLost, 0);
      });

      test('trusts streams without journal', () {
        receiver = create(
          config: MidiRtpSessionConfig.appleMidi.copyWith(journal: false),
        );
        MidiRtpPacket plain(int seq, List<MidiRtpCommand> commands) =>
            MidiRtpPacket(
              header: MidiRtpHeader(
                payloadType: 97,
                sequenceNumber: seq,
                timestamp: 0,
                ssrc: 1,
              ),
              payload: MidiRtpPayload(commands: commands),
            );
        receiver.receivePacket(
          plain(1, [
            command(const MidiNoteOn(channel: 0, note: 60, velocity: 1)),
          ]),
        );
        expect(receiver.receivePacket(plain(3, [])), isEmpty);
        expect(receiver.packetsLost, 1);
      });

      test('ends a stream whose source changes', () {
        receiver.receivePacket(
          packet(5, [
            command(const MidiNoteOn(channel: 0, note: 60, velocity: 1)),
          ]),
        );
        final messages = receiver.receivePacket(
          packet(100, [command(const MidiStop())], ssrc: 2),
        );
        expect([
          for (final m in messages) m.message,
        ], equals([const MidiNoteOff(channel: 0, note: 60), const MidiStop()]));
        expect(receiver.ssrc, 2);
        expect(receiver.packetsLost, 0);
        expect(
          issues.single,
          'networkLoss: The synchronization source '
          'changed to 2',
        );
      });

      test('assembles System Exclusive segments', () {
        receiver.receivePacket(
          packet(1, [
            MidiRtpSysExCommand(kind: MidiRtpSysExKind.first, data: [1]),
          ], timestamp: 5),
        );
        final messages = receiver.receivePacket(
          packet(2, [
            MidiRtpSysExCommand(kind: MidiRtpSysExKind.middle, data: [2]),
            MidiRtpSysExCommand(
              deltaTime: 1,
              kind: MidiRtpSysExKind.last,
              data: [3],
            ),
            MidiRtpSysExCommand(
              deltaTime: 1,
              kind: MidiRtpSysExKind.complete,
              data: [4],
            ),
          ], timestamp: 9),
        );
        expect(
          messages,
          equals([
            (message: MidiSysEx([1, 2, 3]), time: const MidiTime(500)),
            (message: MidiSysEx([4]), time: const MidiTime(1100)),
          ]),
        );
      });

      test('drops segments without a start and overlong commands', () {
        receiver = create(maxSysExLength: 2);
        expect(
          receiver.receivePacket(
            packet(1, [
              MidiRtpSysExCommand(kind: MidiRtpSysExKind.last, data: [1]),
              MidiRtpSysExCommand(kind: MidiRtpSysExKind.first, data: [1, 2]),
              MidiRtpSysExCommand(kind: MidiRtpSysExKind.middle, data: [3]),
              MidiRtpSysExCommand(kind: MidiRtpSysExKind.last, data: [4]),
              MidiRtpSysExCommand(
                kind: MidiRtpSysExKind.complete,
                data: [1, 2, 3],
              ),
              MidiRtpSysExCommand(kind: MidiRtpSysExKind.first, data: [1]),
              MidiRtpSysExCommand(kind: MidiRtpSysExKind.cancel),
            ]),
          ),
          isEmpty,
        );
        expect(
          issues,
          equals([
            'sysExIncomplete: A System Exclusive segment without its start '
                'was dropped',
            'sysExTooLong: A System Exclusive command exceeded 2 octets',
            'sysExIncomplete: A System Exclusive segment without its start '
                'was dropped',
            'sysExTooLong: A System Exclusive command exceeded 2 octets',
          ]),
        );
      });

      test('delivers undefined system commands as UMP', () {
        final messages = receiver.receivePacket(
          packet(1, [
            MidiRtpUndefinedCommand(status: 0xF4, data: [1, 2]),
            MidiRtpUndefinedCommand(status: 0xF5, data: [1, 2, 3]),
            MidiRtpUndefinedCommand(status: 0xFD),
            const MidiRtpEmptyCommand(deltaTime: 4),
          ]),
        );
        expect(
          [for (final m in messages) m.message],
          equals([
            MidiRtpJournalRepair.undefinedMessage(0xF4, const [1, 2]),
            MidiRtpJournalRepair.undefinedMessage(0xFD, const []),
          ]),
        );
        expect(receiver.model.system.undefinedCount(0xF5), 1);
        expect(issues.single, startsWith('untranslatable: Undefined command'));
      });
    });

    group('close(time)', () {
      test('ends the notes and expects a new stream', () {
        receiver.receivePacket(
          packet(5, [
            command(const MidiNoteOn(channel: 0, note: 60, velocity: 1)),
          ], timestamp: 3),
        );
        expect(
          receiver.close(),
          equals([
            (
              message: const MidiNoteOff(channel: 0, note: 60),
              time: const MidiTime(300),
            ),
          ]),
        );
        expect(receiver.feedbackSequenceNumber, isNull);
        expect(receiver.close(time: const MidiTime(9)), isEmpty);
        expect(receiver.receivePacket(packet(1, [])), isEmpty);
        expect(receiver.packetsReceived, 2);
      });
    });

    group('fields', () {
      test('hold the construction arguments', () {
        expect(receiver.config, MidiRtpSessionConfig.appleMidi);
        expect(receiver.clock, const MidiRtpClock(rate: 10000));
        expect(receiver.maxSysExLength, 1 << 20);
        expect(receiver.onIssue, isNotNull);
        expect(MidiRtpReceiver().ssrc, isNull);
      });
    });

    // .........................................................................
    group('with MidiRtpSender over a lossy channel', () {
      // Sends a random but realistic stream through MidiRtpLossyChannel:
      // notes with overlaps, controllers and channel mode messages, programs
      // with banks, canonical RPN and NRPN transactions, pitch wheel,
      // pressure, legal MIDI Time Code, the sequencer, System Exclusive of
      // every size and Reset State commands. The session configuration
      // alternates between per-chapter semantics, anchored chapters and the
      // defaults. The guard packet at the end closes the stream.
      _Result session({
        required int seed,
        required MidiRtpSendingPolicy policy,
        Duration recentNoteOn = const Duration(days: 1),
        int step = 2000,
        int steps = 300,
        double feedbackRate = 0.5,
        int? variant,
      }) {
        final random = Random(seed);
        var piece = 0;
        var reverse = false;

        List<MidiMessage> next() {
          final ch = random.nextInt(3);
          int v() => random.nextInt(128);
          int note() => 60 + random.nextInt(8);
          MidiControlChange cc(int controller, int value) => MidiControlChange(
            channel: ch,
            controller: controller,
            value: value,
          );
          switch (random.nextInt(30)) {
            case 0 || 1 || 2 || 3:
              return [
                MidiNoteOn(channel: ch, note: note(), velocity: 1 + v() % 127),
              ];
            case 4 || 5 || 6:
              return [MidiNoteOff(channel: ch, note: note(), velocity: v())];
            case 7:
              return [MidiNoteOn(channel: ch, note: note(), velocity: 0)];
            case 8 || 9:
              const numbers = [1, 2, 7, 10, 11, 64, 65, 66, 67, 0, 32, 74, 66];
              return [cc(numbers[random.nextInt(numbers.length)], v())];
            case 10:
              return [cc(120 + random.nextInt(8), random.nextBool() ? 0 : v())];
            case 11:
              return [MidiProgramChange(channel: ch, program: v())];
            case 12:
              return [
                MidiPitchBend(channel: ch, value: random.nextInt(0x4000)),
              ];
            case 13:
              return [MidiChannelPressure(channel: ch, pressure: v())];
            case 14:
              return [
                MidiPolyPressure(channel: ch, note: note(), pressure: v()),
              ];
            case 15 || 16 || 17:
              final nrpn = random.nextBool();
              final msb = cc(nrpn ? 99 : 101, random.nextInt(2));
              return switch (random.nextInt(3)) {
                0 => [msb, cc(nrpn ? 98 : 100, random.nextInt(3))],
                1 => [msb, cc(6, v())],
                _ => [cc(nrpn ? 99 : 101, 127), cc(nrpn ? 98 : 100, 127)],
              };
            case 18 || 19:
              return [
                cc(const [6, 38, 96, 97][random.nextInt(4)], v()),
              ];
            case 20:
              final length = 1 + random.nextInt(4);
              return [
                MidiSysEx([for (var i = 0; i < length; i++) v()]),
              ];
            case 21:
              final length = 100 + random.nextInt(400);
              return [
                MidiSysEx([for (var i = 0; i < length; i++) v()]),
              ];
            case 22:
              const sequencer = [
                MidiStart(),
                MidiStop(),
                MidiContinue(),
                MidiTimingClock(),
                MidiTimingClock(),
                MidiTimingClock(),
              ];
              return [sequencer[random.nextInt(sequencer.length)]];
            case 23:
              return [MidiSongPositionPointer(position: random.nextInt(100))];
            case 24:
              if (random.nextInt(20) == 0) reverse = !reverse;
              final current = piece;
              piece = (current + (reverse ? 7 : 1)) % 8;
              final value = random.nextInt(16) & (current.isOdd ? 1 : 15);
              return [MidiTimeCodeQuarterFrame(piece: current, value: value)];
            case 25:
              return [
                MidiSysEx([
                  0x7F,
                  0x7F,
                  0x01,
                  0x01,
                  random.nextInt(24),
                  random.nextInt(60),
                  random.nextInt(60),
                  random.nextInt(30),
                ]),
              ];
            case 26:
              return [MidiSongSelect(song: v())];
            case 27:
              return [
                random.nextBool()
                    ? const MidiTuneRequest()
                    : const MidiActiveSensing(),
              ];
            case 28:
              return [
                random.nextInt(4) == 0
                    ? const MidiSystemReset()
                    : const MidiActiveSensing(),
              ];
            default:
              return [
                random.nextInt(4) == 0
                    ? MidiSysEx(const [0x7E, 0x7F, 0x09, 0x01])
                    : const MidiTimingClock(),
              ];
          }
        }

        final fmtp = switch (variant ?? seed % 3) {
          0 => MidiRtpFmtp.parse(
            'a=fmtp:97 ch_default=C135.138.192; ch_anchor=P; ch_never=0E',
          ),
          1 => MidiRtpFmtp.parse(
            'a=fmtp:97 ch_anchor=0-15CW; ch_default=0C64.192-194',
          ),
          _ => MidiRtpFmtp(payloadType: 97),
        };
        final config = MidiRtpSessionConfig.fromFmtp(fmtp, clockRate: 10000)
            .copyWith(
              sendingPolicy: policy,
              maxPacketSize: random.nextBool() ? 1472 : 200,
            );
        final sender = MidiRtpSender(
          config: config,
          ssrc: seed,
          sequenceNumber: random.nextInt(0x10000),
          recentNoteOn: recentNoteOn,
          openLoopWindow: 1 << 20,
        );
        final receiver = MidiRtpReceiver(config: config);
        final rendered = MidiRtpStreamState();
        final network = MidiRtpLossyChannel(
          seed: seed,
          lossRate: 0.1 + random.nextDouble() * 0.4,
          burstLossRate: 0.05,
          reorderRate: 0.05,
          duplicateRate: 0.05,
        );
        void deliver(List<List<int>> packets) {
          for (final bytes in packets) {
            for (final timed in receiver.receive(bytes)) {
              rendered.apply(timed.message);
            }
          }
        }

        var maxJournal = 0;
        var journals = 0;
        var packets = 0;
        var time = 0;
        for (var i = 0; i < steps; i++) {
          time += random.nextInt(step);
          final count = 1 + random.nextInt(4);
          final messages = [
            for (var j = 0; j < count; j++)
              for (final message in next())
                (message: message, time: MidiTime(time)),
          ];
          for (final packet in sender.send(messages)) {
            maxJournal = max(maxJournal, sender.journalLength);
            journals += sender.journalLength;
            packets++;
            network.send(packet.toBytes());
          }
          deliver(network.receive());
          final feedback = receiver.feedbackSequenceNumber;
          if (feedback != null && random.nextDouble() < feedbackRate) {
            sender.acknowledge(feedback);
          }
        }
        deliver(network.flush());
        deliver([sender.guard(time: MidiTime(time + 1000)).toBytes()]);
        return (
          sender: sender.history.snapshot(),
          receiver: rendered.snapshot(),
          maxJournal: maxJournal,
          meanJournal: journals / packets,
          lost: receiver.packetsLost,
          recovered: receiver.packetsRecovered,
        );
      }

      for (final policy in MidiRtpSendingPolicy.values) {
        test('converges to the sender state (${policy.name})', () {
          var lost = 0;
          var recovered = 0;
          for (var seed = 0; seed < 90; seed++) {
            final result = session(seed: seed, policy: policy);
            expect(result.receiver, result.sender, reason: 'seed $seed');
            lost += result.lost;
            recovered += result.recovered;
          }
          expect(lost, greaterThan(5000));
          expect(recovered, greaterThan(lost ~/ 2));
        });
      }

      test('leaves no hanging notes when lost NoteOns are skipped', () {
        for (var seed = 0; seed < 60; seed++) {
          final result = session(
            seed: seed,
            policy: MidiRtpSendingPolicy.closedLoop,
            recentNoteOn: const Duration(milliseconds: 100),
            step: 200000,
          );
          final receiver = {...result.receiver};
          final sender = {...result.sender};
          for (final key in {...receiver.keys, ...sender.keys}) {
            if (key == 'system') continue;
            final r = {...?receiver[key] as Map<String, Object?>?};
            final s = {...?sender[key] as Map<String, Object?>?};
            final rNotes = (r.remove('notes') as Map?) ?? const {};
            final sNotes = (s.remove('notes') as Map?) ?? const {};
            for (final note in rNotes.keys) {
              expect(sNotes[note], rNotes[note], reason: 'seed $seed $key');
            }
            receiver[key] = r;
            sender[key] = s;
          }
          expect(receiver, sender, reason: 'seed $seed');
        }
      });

      test('keeps the journal bounded under closed-loop feedback', () {
        for (var seed = 1; seed <= 3; seed++) {
          _Result run(MidiRtpSendingPolicy policy, {int steps = 3000}) =>
              session(
                seed: seed,
                policy: policy,
                steps: steps,
                feedbackRate: 1,
                variant: 2,
              );
          final short = run(MidiRtpSendingPolicy.closedLoop, steps: 300);
          final long = run(MidiRtpSendingPolicy.closedLoop);
          final anchor = run(MidiRtpSendingPolicy.anchor);
          expect(long.receiver, long.sender);
          expect(long.meanJournal, lessThan(short.meanJournal * 1.5));
          expect(long.meanJournal * 3, lessThan(anchor.meanJournal));
          expect(long.maxJournal, lessThanOrEqualTo(anchor.maxJournal));
        }
      });
    });
  });
}

typedef _Result = ({
  Map<String, Object?> sender,
  Map<String, Object?> receiver,
  int maxJournal,
  double meanJournal,
  int lost,
  int recovered,
});
