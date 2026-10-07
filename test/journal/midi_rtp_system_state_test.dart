// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSystemState', () {
    late MidiRtpSystemState state;

    setUp(() => state = MidiRtpSystemState());

    void qf(int piece, int value, {int seq = 1}) => state.apply(
      MidiTimeCodeQuarterFrame(piece: piece, value: value),
      seq: seq,
    );

    group('simple system commands', () {
      test('count Reset, Tune Request and Active Sense', () {
        state
          ..apply(const MidiSystemReset(), seq: 2)
          ..apply(const MidiTuneRequest(), seq: 3)
          ..apply(const MidiTuneRequest(), seq: 4)
          ..apply(const MidiActiveSensing(), seq: 5)
          ..apply(const MidiSongSelect(song: 9), seq: 6);
        expect(state.resetCount, 1);
        expect(state.resetSeq, 2);
        expect(state.tuneRequestCount, 2);
        expect(state.tuneRequestSeq, 4);
        expect(state.activeSenseCount, 1);
        expect(state.activeSenseSeq, 5);
        expect(state.songSelect, (value: 9, seq: 6));
      });

      test('count modulo 128', () {
        for (var i = 0; i < 130; i++) {
          state.apply(const MidiActiveSensing());
        }
        expect(state.activeSenseCount, 2);
      });
    });

    group('sequencer', () {
      ({bool running, bool downbeat, int position, bool startRecent}) seq() =>
          state.sequencer;

      test('follows Start, Clock, Stop, Continue and Song Position', () {
        state.apply(const MidiTimingClock(), seq: 1);
        expect(state.sequencerSeq, isNull);
        state.apply(const MidiStart(), seq: 2);
        expect(seq(), (
          running: true,
          downbeat: false,
          position: 0,
          startRecent: true,
        ));
        state.apply(const MidiTimingClock(), seq: 3);
        expect(seq().downbeat, isTrue);
        expect(seq().position, 0);
        state.apply(const MidiTimingClock(), seq: 4);
        expect(seq().position, 1);
        state.apply(const MidiStop(), seq: 5);
        state.apply(const MidiTimingClock(), seq: 6);
        expect(seq(), (
          running: false,
          downbeat: true,
          position: 1,
          startRecent: true,
        ));
        expect(state.sequencerSeq, 5);
        state.apply(const MidiStop(), seq: 7);
        expect(state.sequencerSeq, 5);
        state.apply(const MidiSongPositionPointer(position: 4), seq: 8);
        expect(seq().position, 24);
        expect(seq().downbeat, isFalse);
        state.apply(const MidiContinue(), seq: 9);
        expect(seq(), (
          running: true,
          downbeat: false,
          position: 24,
          startRecent: false,
        ));
        expect(state.sequencerSeq, 9);
      });
    });

    group('time code', () {
      test('completes forward frames two frames ahead', () {
        const code = MidiRtpTimeCode(
          hours: 1,
          minutes: 2,
          seconds: 3,
          frames: 4,
        );
        final nibbles = code.toNibbles();
        for (var piece = 0; piece < 7; piece++) {
          qf(piece, nibbles[piece], seq: piece + 1);
          expect(state.partialFrame?.point, piece);
          expect(state.reverse, isFalse);
        }
        expect(
          state.partialFrame?.field,
          code.toField(nibbles: true) & 0xFFFFFFF0,
        );
        qf(7, nibbles[7], seq: 8);
        expect(state.partialFrame, isNull);
        expect(state.completeFrame, (
          field: code.advance(2).toField(nibbles: true),
          q: true,
          seq: 8,
        ));
        expect(state.timeCodeSeq, 8);
      });

      test('completes reverse frames without offset', () {
        const code = MidiRtpTimeCode(minutes: 5, frames: 9);
        final nibbles = code.toNibbles();
        for (var piece = 7; piece > 0; piece--) {
          qf(piece, nibbles[piece]);
          expect(state.partialFrame?.point, piece);
          expect(state.reverse, isTrue);
        }
        qf(0, nibbles[0]);
        expect(state.completeFrame!.field, code.toField(nibbles: true));
        expect(state.reverse, isTrue);
      });

      test('drops the partial frame of a broken sequence', () {
        qf(0, 1);
        qf(1, 0);
        qf(5, 2);
        expect(state.partialFrame, isNull);
        qf(4, 2);
        expect(state.reverse, isTrue);
        qf(5, 2);
        expect(state.reverse, isFalse);
      });

      test('takes a Full Frame message as complete frame', () {
        qf(0, 1);
        final completed = state.applySysEx(MidiRtpSysExKind.complete, [
          0x7F,
          0x7F,
          0x01,
          0x01,
          0x21,
          2,
          3,
          4,
        ], seq: 5);
        expect(completed, equals([0x7F, 0x7F, 0x01, 0x01, 0x21, 2, 3, 4]));
        expect(state.completeFrame, (field: 0x21020304, q: false, seq: 5));
        expect(state.partialFrame, isNull);
        expect(state.sysEx.single.fullFrame, isTrue);
        expect(state.snapshot()['sysEx'], isNull);
      });

      test('locate sets the complete frame without a record', () {
        qf(7, 1);
        state.locate(const MidiRtpTimeCode(hours: 2), seq: 4);
        expect(state.completeFrame, (field: 0x02000000, q: false, seq: 4));
        expect(state.partialFrame, isNull);
        expect(state.reverse, isFalse);
        expect(state.timeCodeSeq, 4);
        expect(state.sysEx, isEmpty);
        expect(state.sysExCount, 0);
      });
    });

    group('applySysEx(kind, data, droppedF7, seq, order, count)', () {
      test('records complete commands', () {
        final completed = state.applySysEx(
          MidiRtpSysExKind.complete,
          [1, 2],
          droppedF7: true,
          seq: 3,
          order: 4,
        );
        expect(completed, equals([1, 2]));
        final record = state.sysEx.single;
        expect(record.data, equals([1, 2]));
        expect(record.status, MidiRtpSysExStatus.droppedF7);
        expect(record.count, 1);
        expect(record.chunks, equals([(seq: 3, offset: 0)]));
        expect(record.seq, 3);
        expect(record.order, 4);
        expect(record.fullFrame, isFalse);
        expect(state.sysExCount, 1);
        expect(state.unfinishedSysEx, isNull);
      });

      test('assembles segments over packets', () {
        expect(state.applySysEx(MidiRtpSysExKind.first, [1], seq: 1), isNull);
        expect(state.applySysEx(MidiRtpSysExKind.middle, [2], seq: 1), isNull);
        expect(state.unfinishedSysEx!.chunks, equals([(seq: 1, offset: 0)]));
        expect(state.applySysEx(MidiRtpSysExKind.middle, [3], seq: 2), isNull);
        expect(state.unfinishedSysEx!.data, equals([1, 2, 3]));
        expect(
          state.applySysEx(MidiRtpSysExKind.last, [], seq: 3),
          equals([1, 2, 3]),
        );
        final record = state.sysEx.single;
        expect(record.status, MidiRtpSysExStatus.finished);
        expect(
          record.chunks,
          equals([
            (seq: 1, offset: 0),
            (seq: 2, offset: 2),
            (seq: 3, offset: 3),
          ]),
        );
        expect(record.seq, 3);
        expect(state.snapshot()['sysEx'], equals([1, 2, 3]));
      });

      test('cancels a command', () {
        state.applySysEx(MidiRtpSysExKind.first, [1]);
        expect(state.applySysEx(MidiRtpSysExKind.cancel, []), isNull);
        expect(state.sysEx.single.status, MidiRtpSysExStatus.cancelled);
        expect(state.unfinishedSysEx, isNull);
        expect(state.sysExCount, 1);
      });

      test('ignores segments without a start', () {
        for (final kind in [
          MidiRtpSysExKind.middle,
          MidiRtpSysExKind.last,
          MidiRtpSysExKind.cancel,
        ]) {
          expect(state.applySysEx(kind, [1]), isNull);
        }
        expect(state.sysEx, isEmpty);
      });

      test('counts only commands the predicate and count accept', () {
        state = MidiRtpSystemState(countsSysEx: (data) => data.first != 0);
        state
          ..applySysEx(MidiRtpSysExKind.complete, [0])
          ..applySysEx(MidiRtpSysExKind.complete, [1])
          ..applySysEx(MidiRtpSysExKind.complete, [2], count: false);
        expect(state.sysExCount, 1);
        expect([for (final r in state.sysEx) r.count], equals([0, 1, 1]));
      });
    });

    group('applyUndefined(status, data, seq)', () {
      test('counts and keeps the most recent command', () {
        state
          ..applyUndefined(0xF4, [1], seq: 2)
          ..applyUndefined(0xF4, [2, 3], seq: 3);
        expect(state.undefinedCount(0xF4), 2);
        expect(state.undefined(0xF4)!.data, equals([2, 3]));
        expect(state.undefined(0xF4)!.seq, 3);
        expect(state.undefinedCount(0xF9), 0);
        expect(state.undefined(0xF9), isNull);
      });

      test('syncUndefinedCount sets a count', () {
        state
          ..syncUndefinedCount(0xFD, 7)
          ..applyUndefined(0xF5, [1], seq: 4)
          ..syncUndefinedCount(0xF5, 300);
        expect(state.undefinedCount(0xFD), 7);
        expect(state.undefined(0xFD), isNull);
        expect(state.undefinedCount(0xF5), 300 & 0xFF);
        expect(state.undefined(0xF5)!.data, equals([1]));
        expect(state.undefined(0xF5)!.seq, 4);
      });
    });

    group('reset(keepLastSysEx)', () {
      test('ends the activity and keeps the reference counts', () {
        state
          ..apply(const MidiSystemReset(), seq: 1)
          ..apply(const MidiTuneRequest(), seq: 1)
          ..apply(const MidiSongSelect(song: 1), seq: 1)
          ..apply(const MidiActiveSensing(), seq: 1)
          ..apply(const MidiStart(), seq: 1)
          ..applyUndefined(0xF4, [1], seq: 1)
          ..applySysEx(MidiRtpSysExKind.complete, [5]);
        qf(0, 1);
        state.reset();
        expect(state.resetSeq, isNull);
        expect(state.tuneRequestSeq, isNull);
        expect(state.songSelect, isNull);
        expect(state.activeSenseSeq, isNull);
        expect(state.undefined(0xF4), isNull);
        expect(state.undefinedCount(0xF4), 1);
        expect(state.sequencer.running, isFalse);
        expect(state.sequencerSeq, isNull);
        expect(state.partialFrame, isNull);
        expect(state.completeFrame, isNull);
        expect(state.timeCodeSeq, isNull);
        expect(state.sysEx, isEmpty);
        expect([
          state.resetCount,
          state.tuneRequestCount,
          state.activeSenseCount,
        ], equals([1, 1, 1]));
        expect(state.sysExCount, 1);
        expect(state.snapshot(), isEmpty);
      });

      test('keeps the Reset State command itself', () {
        state
          ..applySysEx(MidiRtpSysExKind.complete, [1])
          ..applySysEx(MidiRtpSysExKind.complete, [0x7E, 0x7F, 0x09, 0x01])
          ..reset(keepLastSysEx: true);
        expect(state.sysEx.single.data, equals([0x7E, 0x7F, 0x09, 0x01]));
        expect(state.snapshot(), {
          'sysEx': [0x7E, 0x7F, 0x09, 0x01],
        });
      });
    });

    group('trim(checkpoint, keep)', () {
      test('drops old commands but the unfinished one and kept ones', () {
        state
          ..applySysEx(MidiRtpSysExKind.complete, [1], seq: 1)
          ..applySysEx(MidiRtpSysExKind.complete, [2], seq: 2)
          ..applySysEx(MidiRtpSysExKind.first, [3], seq: 1);
        state.trim(5, keep: (data) => data.first == 2);
        expect([for (final r in state.sysEx) r.data.first], equals([2, 3]));
        state.trim(5);
        expect([for (final r in state.sysEx) r.data.first], equals([3]));
      });
    });

    group('syncCounts()', () {
      test('sets reference counts', () {
        state.syncCounts(
          resetCount: 130,
          tuneRequestCount: 129,
          activeSenseCount: 1,
          sysExCount: 257,
        );
        expect([
          state.resetCount,
          state.tuneRequestCount,
          state.activeSenseCount,
          state.sysExCount,
        ], equals([2, 1, 1, 1]));
        state.syncCounts();
        expect(state.sysExCount, 1);
      });
    });

    group('snapshot()', () {
      test('describes song, sequencer, time code and System Exclusive', () {
        state
          ..apply(const MidiSongSelect(song: 3))
          ..apply(const MidiStart())
          ..applySysEx(MidiRtpSysExKind.complete, [
            0x7F,
            0x7F,
            0x01,
            0x01,
            0x01,
            0x02,
            0x03,
            0x04,
          ])
          ..applySysEx(MidiRtpSysExKind.complete, [9]);
        qf(0, 5);
        expect(state.snapshot(), {
          'songSelect': 3,
          'sequencer': [true, 0, false],
          'timeCode': 'MidiRtpTimeCode(1:2:3:4, rate: 0)',
          'partialTimeCode': [false, 0, 0x50000000],
          'sysEx': [9],
        });
      });
    });

    group('isFullFrame(data) and isResetState(data)', () {
      test('recognise the special System Exclusive commands', () {
        expect(
          MidiRtpSystemState.isFullFrame([0x7F, 0x00, 0x01, 0x01, 1, 2, 3, 4]),
          isTrue,
        );
        for (final data in [
          [0x7F, 0x00, 0x01, 0x02, 1, 2, 3, 4],
          [0x7F, 0x00, 0x02, 0x01, 1, 2, 3, 4],
          [0x7E, 0x00, 0x01, 0x01, 1, 2, 3, 4],
          [0x7F, 0x00, 0x01, 0x01, 1, 2, 3],
        ]) {
          expect(MidiRtpSystemState.isFullFrame(data), isFalse);
        }
        for (final sub in [0, 1, 2, 3]) {
          expect(MidiRtpSystemState.isResetState([0x7E, 0x7F, 9, sub]), isTrue);
        }
        for (final sub in [1, 2]) {
          expect(
            MidiRtpSystemState.isResetState([0x7E, 0x7F, 0x0A, sub]),
            isTrue,
          );
        }
        for (final data in [
          [0x7E, 0x7F, 9, 4],
          [0x7E, 0x7F, 0x0A, 3],
          [0x7F, 0x7F, 9, 1],
          [0x7E, 0x7F, 9],
        ]) {
          expect(MidiRtpSystemState.isResetState(data), isFalse);
        }
      });
    });
  });
}
