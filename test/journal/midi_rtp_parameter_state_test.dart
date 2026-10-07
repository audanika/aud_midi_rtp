// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpParameterState', () {
    late MidiRtpParameterState state;
    var order = 0;

    void cc(int controller, int value, {int seq = 1}) =>
        state.apply(controller, value, seq: seq, order: ++order);

    setUp(() {
      state = MidiRtpParameterState();
      order = 0;
    });

    group('handles(controller)', () {
      test('takes 98 to 101 always and data entry while selected', () {
        expect(state.handles(99), isTrue);
        expect(state.handles(100), isTrue);
        expect(state.handles(6), isFalse);
        expect(state.handles(7), isFalse);
        cc(101, 0);
        for (final controller in [6, 38, 96, 97]) {
          expect(state.handles(controller), isTrue);
        }
        expect(state.handles(7), isFalse);
      });
    });

    group('apply(controller, value, seq, order)', () {
      test('selects an RPN with an MSB and LSB pair', () {
        cc(101, 1, seq: 4);
        expect(state.selection, (nrpn: false, number: 128, pending: true));
        expect(state.pending, (value: 1, nrpn: false));
        expect(state.inProgress, isFalse);
        expect(state.selectionSeq, 4);
        cc(100, 2, seq: 5);
        expect(state.selection, (nrpn: false, number: 130, pending: false));
        expect(state.pending, isNull);
        expect(state.inProgress, isTrue);
        expect(state.selectionSeq, isNull);
        expect(state.parameter(nrpn: false, number: 130)?.seq, 5);
      });

      test('closes the selection with the null parameter', () {
        cc(99, 127);
        cc(98, 127, seq: 6);
        expect(state.selection, isNull);
        expect(state.inProgress, isFalse);
        expect(state.selectionSeq, 6);
        expect(state.handles(6), isFalse);
      });

      test('takes a lone LSB with the most recent MSB (type 2)', () {
        cc(99, 3);
        cc(98, 1);
        cc(98, 2);
        expect(state.selection, (
          nrpn: true,
          number: 3 << 7 | 2,
          pending: false,
        ));
        cc(100, 9);
        expect(state.selection, (nrpn: false, number: 9, pending: false));
      });

      test('starts a transaction with data after a lone MSB (type 3)', () {
        cc(101, 0);
        cc(6, 12, seq: 3);
        expect(state.selection, (nrpn: false, number: 0, pending: false));
        expect(state.inProgress, isTrue);
        expect(state.parameter(nrpn: false, number: 0)?.entryMsb, (
          value: 12,
          x: false,
          seq: 3,
        ));
      });

      test('tracks entries and data increments', () {
        cc(101, 0);
        cc(100, 0);
        cc(38, 5, seq: 2);
        cc(96, 0, seq: 3);
        cc(96, 0, seq: 3);
        cc(97, 0, seq: 4);
        var p = state.parameter(nrpn: false, number: 0)!;
        expect(p.entryMsb, isNull);
        expect(p.entryLsb, (value: 5, x: false, seq: 2));
        expect(p.aButton, (count: 1, x: false, seq: 4));
        expect(p.cButton, 1);
        cc(6, 7, seq: 5);
        p = state.parameter(nrpn: false, number: 0)!;
        expect(p.entryMsb, (value: 7, x: false, seq: 5));
        expect(p.entryLsb, isNull);
        expect(p.aButton, isNull);
        expect(p.cButton, 0);
        cc(38, 8, seq: 6);
        expect(state.parameter(nrpn: false, number: 0)!.entryLsb, (
          value: 8,
          x: false,
          seq: 6,
        ));
      });

      test('limits the increment count to 14 bits', () {
        cc(101, 0);
        cc(100, 0);
        for (var i = 0; i < 0x4001; i++) {
          cc(97, 0);
        }
        expect(
          state.parameter(nrpn: false, number: 0)!.aButton!.count,
          -0x3FFF,
        );
        expect(state.parameter(nrpn: false, number: 0)!.cButton, -0x3FFF);
      });
    });

    group('resetAllControllers()', () {
      test('closes the selection and flags older values', () {
        cc(101, 0);
        cc(100, 1);
        cc(6, 1);
        cc(38, 2);
        cc(96, 0);
        cc(101, 0);
        cc(100, 2);
        state.resetAllControllers();
        expect(state.selection, isNull);
        expect(state.pending, isNull);
        expect(state.inProgress, isFalse);
        expect(state.selectionSeq, isNull);
        final p = state.parameter(nrpn: false, number: 1)!;
        expect(p.entryMsb!.x, isTrue);
        expect(p.entryLsb!.x, isTrue);
        expect(p.aButton!.x, isTrue);
        expect(p.cButton, 0);
        expect(state.parameter(nrpn: false, number: 2)!.entryMsb, isNull);
        cc(100, 5);
        expect(state.selection, (nrpn: false, number: 5, pending: false));
      });
    });

    group('reset()', () {
      test('forgets every parameter', () {
        cc(101, 0);
        cc(100, 1);
        cc(6, 1);
        state.reset();
        expect(state.parameters, isEmpty);
        expect(state.selection, isNull);
      });
    });

    group('parameters', () {
      test('lists parameters oldest transaction first', () {
        cc(99, 0);
        cc(98, 1);
        cc(99, 0);
        cc(98, 2);
        cc(99, 0);
        cc(98, 1);
        expect([
          for (final p in state.parameters) (p.nrpn, p.number),
        ], equals([(true, 2), (true, 1)]));
      });
    });

    group('snapshot()', () {
      test('describes selection and values', () {
        expect(state.snapshot(), {
          'selection': null,
          'values': <String, Object?>{},
        });
        cc(99, 0);
        cc(98, 1);
        cc(6, 9);
        cc(101, 0);
        cc(100, 3);
        cc(96, 0);
        cc(101, 1);
        expect(state.snapshot(), {
          'selection': 'rpn:128?',
          'values': {
            'nrpn:1': [9, null, 0],
            'rpn:3': [null, null, 1],
          },
        });
      });
    });
  });
}
