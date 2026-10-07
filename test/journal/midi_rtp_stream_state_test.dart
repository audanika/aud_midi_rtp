// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpStreamState', () {
    late MidiRtpStreamState state;

    setUp(() => state = MidiRtpStreamState());

    group('MidiRtpStreamState(isEnhanced, countsSysEx)', () {
      test('creates 16 channels and the system state', () {
        expect([
          for (final c in state.channels) c.channel,
        ], equals(List.generate(16, (i) => i)));
      });

      test('passes the enhanced controllers and the COUNT predicate', () {
        state = MidiRtpStreamState(
          isEnhanced: (channel, controller) => channel == 1 && controller == 2,
          countsSysEx: (data) => false,
        );
        state
          ..apply(const MidiControlChange(channel: 1, controller: 2, value: 3))
          ..apply(const MidiControlChange(channel: 0, controller: 2, value: 3))
          ..apply(MidiSysEx([1]));
        expect(state.channels[1].controllerHistory(2), hasLength(1));
        expect(state.channels[0].controllerHistory(2), isEmpty);
        expect(state.system.sysExCount, 0);
      });
    });

    group('apply(message, seq, time)', () {
      test('routes channel and system messages', () {
        state
          ..apply(
            const MidiNoteOn(channel: 5, note: 60, velocity: 9),
            seq: 3,
            time: const MidiTime(7),
          )
          ..apply(const MidiSongSelect(song: 2), seq: 4)
          ..apply(MidiSysEx([1, 2]), seq: 5)
          ..apply(const MidiNoteOn2(channel: 0, note: 1, velocity: 2));
        expect(state.channels[5].note(60)!.seq, 3);
        expect(state.channels[5].note(60)!.time, const MidiTime(7));
        expect(state.system.songSelect!.value, 2);
        expect(state.system.sysEx.single.seq, 5);
        expect(state.hasSoundingNotes, isTrue);
      });

      test('resets everything on System Reset and counts it', () {
        state
          ..apply(const MidiNoteOn(channel: 5, note: 60, velocity: 9))
          ..apply(const MidiSongSelect(song: 2))
          ..apply(const MidiSystemReset(), seq: 6);
        expect(state.hasSoundingNotes, isFalse);
        expect(state.system.songSelect, isNull);
        expect(state.system.resetCount, 1);
        expect(state.system.resetSeq, 6);
      });
    });

    group('applySysEx(kind, data, droppedF7, seq, count)', () {
      test('resets on a Reset State command and keeps it', () {
        state.apply(const MidiProgramChange(channel: 0, program: 3));
        expect(
          state.applySysEx(MidiRtpSysExKind.first, [0x7E, 0x7F], seq: 1),
          isNull,
        );
        expect(state.channels[0].program, isNotNull);
        expect(
          state.applySysEx(MidiRtpSysExKind.last, [0x09, 0x01], seq: 2),
          equals([0x7E, 0x7F, 0x09, 0x01]),
        );
        expect(state.channels[0].program, isNull);
        expect(state.system.sysEx.single.data, equals([0x7E, 0x7F, 9, 1]));
      });

      test('passes dropped 0xF7 and count', () {
        state.applySysEx(
          MidiRtpSysExKind.complete,
          [1],
          droppedF7: true,
          count: false,
        );
        expect(state.system.sysEx.single.status, MidiRtpSysExStatus.droppedF7);
        expect(state.system.sysExCount, 0);
      });
    });

    group('applyUndefined(status, data, seq)', () {
      test('applies undefined commands to the system state', () {
        state.applyUndefined(0xF9, const [], seq: 2);
        expect(state.system.undefined(0xF9)!.seq, 2);
      });
    });

    group('trim(checkpoint, keepController, keepSysEx)', () {
      test('trims channel and system histories', () {
        state = MidiRtpStreamState(isEnhanced: (channel, controller) => true);
        state
          ..apply(
            const MidiControlChange(channel: 0, controller: 1, value: 1),
            seq: 1,
          )
          ..apply(
            const MidiControlChange(channel: 1, controller: 1, value: 1),
            seq: 1,
          )
          ..apply(MidiSysEx([1]), seq: 1)
          ..apply(MidiSysEx([2]), seq: 1);
        state.trim(
          2,
          keepController: (channel, controller) => channel == 1,
          keepSysEx: (data) => data.first == 2,
        );
        expect(state.channels[0].controllerHistory(1), isEmpty);
        expect(state.channels[1].controllerHistory(1), hasLength(1));
        expect(state.system.sysEx.single.data, equals([2]));
        state.trim(2);
        expect(state.channels[1].controllerHistory(1), isEmpty);
        expect(state.system.sysEx, isEmpty);
      });
    });

    group('snapshot()', () {
      test('describes the channels that left power-up and the system', () {
        expect(state.snapshot(), {'system': <String, Object?>{}});
        state.apply(const MidiProgramChange(channel: 4, program: 1));
        expect(state.snapshot(), {
          '4': {
            'program': [1],
          },
          'system': <String, Object?>{},
        });
      });
    });
  });
}
