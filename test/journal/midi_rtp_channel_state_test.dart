// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpChannelState', () {
    late MidiRtpChannelState state;
    var order = 0;

    void apply(MidiChannelVoice1Message message, {int seq = 1, int time = 0}) =>
        state.apply(message, seq: seq, order: ++order, time: MidiTime(time));
    void cc(int controller, int value, {int seq = 1}) => apply(
      MidiControlChange(channel: 3, controller: controller, value: value),
      seq: seq,
    );

    setUp(() {
      state = MidiRtpChannelState(channel: 3, enhancedControllers: {16});
      order = 0;
    });

    group('notes', () {
      test('track the most recent note command and the reference count', () {
        apply(
          const MidiNoteOn(channel: 3, note: 60, velocity: 90),
          seq: 2,
          time: 7,
        );
        apply(const MidiNoteOn(channel: 3, note: 60, velocity: 80), seq: 3);
        expect(state.note(60), (
          on: true,
          velocity: 80,
          releaseVelocity: 64,
          count: 2,
          seq: 3,
          order: 2,
          time: MidiTime.zero,
        ));
        apply(const MidiNoteOff(channel: 3, note: 60, velocity: 30), seq: 4);
        expect(state.note(60)!.on, isFalse);
        expect(state.note(60)!.count, 1);
        expect(state.note(60)!.releaseVelocity, 30);
        expect(state.noteOffSeq, 4);
        apply(const MidiNoteOn(channel: 3, note: 60, velocity: 0), seq: 5);
        expect(state.note(60)!.count, 0);
        expect(state.note(60)!.releaseVelocity, 64);
        apply(const MidiNoteOff(channel: 3, note: 61));
        expect(state.note(61)!.count, 0);
        expect(state.note(61)!.velocity, 0);
        expect(state.notes, equals([60, 61]));
      });

      test('setNoteCount changes the reference count', () {
        apply(const MidiNoteOn(channel: 3, note: 60, velocity: 90));
        state
          ..setNoteCount(60, 4)
          ..setNoteCount(61, 4);
        expect(state.note(60)!.count, 4);
        expect(state.note(61), isNull);
      });

      test('hasSoundingNotes tells whether a note is on', () {
        expect(state.hasSoundingNotes, isFalse);
        apply(const MidiNoteOn(channel: 3, note: 60, velocity: 90));
        expect(state.hasSoundingNotes, isTrue);
      });
    });

    group('controllers', () {
      test('track value, count and toggles', () {
        cc(64, 127, seq: 2);
        cc(64, 0, seq: 3);
        cc(64, 10, seq: 4);
        expect(state.controller(64), (
          value: 10,
          count: 3,
          toggles: 2,
          seq: 4,
          order: 3,
        ));
        expect(state.controllerCount(64), 3);
        expect(state.controllerToggles(64), 2);
        expect(state.controllerValue(64), 10);
        expect(state.controllerToggles(7), 1);
        expect(state.controllerToggles(1), 0);
        expect(state.controllerCount(1), 0);
        expect(state.controllers, equals([64]));
      });

      test('keep the commands of enhanced controllers', () {
        cc(16, 1, seq: 2);
        cc(16, 2, seq: 3);
        cc(17, 1);
        expect([
          for (final c in state.controllerHistory(16)) c.value,
        ], equals([1, 2]));
        expect(state.controllerHistory(17), isEmpty);
        state.trim(3);
        expect(state.controllerHistory(16).single.value, 2);
        state.trim(9, keep: (c) => c == 16);
        expect(state.controllerHistory(16), hasLength(1));
        state.trim(9);
        expect(state.controllerHistory(16), isEmpty);
      });

      test('setControllerTools keeps the offset of later toggles', () {
        cc(64, 127);
        cc(121, 0);
        expect(state.controllerToggles(64), 2);
        state.setControllerTools(64, count: 70, toggles: 5);
        expect(state.controller(64)!.count, 6);
        expect(state.controller(64)!.toggles, 5);
        expect(state.controllerCount(64), 6);
        expect(state.controllerToggles(64), 6);
        state.setControllerTools(64);
        expect(state.controller(64)!.toggles, 5);
        state.setControllerTools(65, count: 2, toggles: 3);
        expect(state.controller(65), isNull);
        expect(state.controllerCount(65), 2);
        expect(state.controllerToggles(65), 3);
      });

      test('route parameter system commands to the parameter system', () {
        cc(6, 5);
        expect(state.controller(6)!.value, 5);
        cc(101, 0);
        cc(100, 0);
        cc(6, 9);
        expect(state.controller(6)!.value, 5);
        expect(
          state.parameterSystem.parameter(nrpn: false, number: 0),
          isNotNull,
        );
        expect(state.controller(101), isNull);
      });
    });

    group('program and bank', () {
      test('code the bank of the most recent program change', () {
        apply(const MidiProgramChange(channel: 3, program: 1));
        expect(state.program, (
          program: 1,
          b: false,
          bankMsb: 0,
          x: false,
          bankLsb: 0,
          seq: 1,
        ));
        cc(32, 9);
        cc(0, 5);
        expect(state.bank, (msb: 5, lsb: null));
        apply(const MidiProgramChange(channel: 3, program: 2), seq: 2);
        expect(state.program, (
          program: 2,
          b: true,
          bankMsb: 5,
          x: false,
          bankLsb: 0,
          seq: 2,
        ));
        cc(32, 7);
        cc(121, 0);
        apply(const MidiProgramChange(channel: 3, program: 3), seq: 3);
        expect(state.program, (
          program: 3,
          b: true,
          bankMsb: 5,
          x: true,
          bankLsb: 7,
          seq: 3,
        ));
      });
    });

    group('Reset All Controllers', () {
      test('resets the RP-015 values and ends C-activity', () {
        cc(1, 50);
        cc(11, 20);
        cc(66, 127);
        cc(7, 90);
        apply(const MidiPitchBend(channel: 3, value: 100));
        apply(const MidiChannelPressure(channel: 3, pressure: 5));
        apply(const MidiPolyPressure(channel: 3, note: 60, pressure: 6));
        cc(121, 0);
        expect(state.controllerValue(1), 0);
        expect(state.controllerValue(11), 127);
        expect(state.controllerValue(66), 0);
        expect(state.controllerValue(64), 0);
        expect(state.controllerValue(7), 90);
        expect(state.controller(1)!.value, 50);
        expect(state.pitchWheel, isNull);
        expect(state.channelPressure, isNull);
        expect(state.polyPressure(60), isNull);
        expect(state.snapshot(), {
          'controllers': {1: 0, 7: 90, 11: 127, 64: 0, 65: 0, 66: 0, 67: 0},
        });
      });
    });

    group('All Notes Off', () {
      for (final controller in [120, 123, 124, 125, 126, 127]) {
        test('controller $controller ends N-activity', () {
          apply(const MidiNoteOn(channel: 3, note: 60, velocity: 90));
          apply(const MidiChannelPressure(channel: 3, pressure: 5));
          apply(const MidiPolyPressure(channel: 3, note: 60, pressure: 6));
          cc(controller, 0, seq: 2);
          expect(state.note(60), isNull);
          expect(state.notes, isEmpty);
          expect(state.channelPressure, isNull);
          expect(state.polyPressure(60)!.x, isTrue);
          expect(state.polyPressureNotes, equals([60]));
        });
      }
    });

    group('pressure and pitch wheel', () {
      test('track the most recent values', () {
        apply(const MidiPitchBend(channel: 3, value: 300), seq: 2);
        apply(const MidiChannelPressure(channel: 3, pressure: 4), seq: 3);
        apply(const MidiPolyPressure(channel: 3, note: 61, pressure: 5));
        apply(const MidiPolyPressure(channel: 3, note: 60, pressure: 6));
        expect(state.pitchWheel, (value: 300, seq: 2));
        expect(state.channelPressure, (value: 4, seq: 3));
        expect(state.polyPressure(60), (value: 6, x: false, seq: 1, order: 4));
        expect(state.polyPressureNotes, equals([61, 60]));
      });
    });

    group('reset()', () {
      test('returns to power-up', () {
        apply(const MidiNoteOn(channel: 3, note: 60, velocity: 90));
        cc(16, 5);
        cc(0, 1);
        cc(101, 0);
        apply(const MidiProgramChange(channel: 3, program: 1));
        apply(const MidiPitchBend(channel: 3, value: 300));
        apply(const MidiChannelPressure(channel: 3, pressure: 4));
        apply(const MidiPolyPressure(channel: 3, note: 61, pressure: 5));
        state.reset();
        expect(state.snapshot(), isEmpty);
        expect(state.notes, isEmpty);
        expect(state.noteOffSeq, isNull);
        expect(state.controllers, isEmpty);
        expect(state.controllerHistory(16), isEmpty);
        expect(state.program, isNull);
        expect(state.bank, (msb: null, lsb: null));
        expect(state.pitchWheel, isNull);
        expect(state.channelPressure, isNull);
        expect(state.polyPressureNotes, isEmpty);
        expect(state.parameterSystem.selection, isNull);
      });
    });

    group('snapshot()', () {
      test('describes the rendered state', () {
        apply(const MidiNoteOn(channel: 3, note: 60, velocity: 90));
        apply(const MidiNoteOn(channel: 3, note: 61, velocity: 91));
        apply(const MidiNoteOff(channel: 3, note: 61));
        cc(7, 100);
        cc(123, 0);
        apply(const MidiNoteOn(channel: 3, note: 62, velocity: 92));
        cc(0, 2);
        cc(32, 3);
        apply(const MidiProgramChange(channel: 3, program: 4));
        apply(const MidiPitchBend(channel: 3, value: 5));
        apply(const MidiChannelPressure(channel: 3, pressure: 6));
        apply(const MidiPolyPressure(channel: 3, note: 62, pressure: 7));
        apply(const MidiPolyPressure(channel: 3, note: 63, pressure: 0));
        cc(101, 0);
        expect(state.snapshot(), {
          'notes': {62: 92},
          'controllers': {0: 2, 7: 100, 32: 3},
          'program': [4, 2, 3],
          'pitchWheel': 5,
          'channelPressure': 6,
          'polyPressure': {62: 7},
          'parameters': {'selection': 'rpn:0?', 'values': <String, Object?>{}},
        });
        apply(const MidiChannelPressure(channel: 3, pressure: 0));
        apply(const MidiPitchBend(channel: 3, value: MidiPitchBend.center));
        apply(const MidiProgramChange(channel: 3, program: 4));
        state.reset();
        apply(const MidiProgramChange(channel: 3, program: 4));
        expect(state.snapshot(), {
          'program': [4],
        });
      });
    });
  });
}
