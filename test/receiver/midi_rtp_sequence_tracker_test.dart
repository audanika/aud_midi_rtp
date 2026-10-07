// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpSequenceTracker', () {
    late MidiRtpSequenceTracker tracker;

    setUp(() => tracker = MidiRtpSequenceTracker());

    group('track(sequenceNumber)', () {
      test('classifies first, next, gaps, duplicates and late packets', () {
        expect(tracker.highest, isNull);
        expect(tracker.track(100), (
          arrival: MidiRtpArrival.first,
          extended: 100,
          lost: 0,
        ));
        expect(tracker.track(101), (
          arrival: MidiRtpArrival.next,
          extended: 101,
          lost: 0,
        ));
        expect(tracker.track(104), (
          arrival: MidiRtpArrival.afterLoss,
          extended: 104,
          lost: 2,
        ));
        expect(tracker.track(104), (
          arrival: MidiRtpArrival.duplicate,
          extended: 104,
          lost: 0,
        ));
        expect(tracker.track(102), (
          arrival: MidiRtpArrival.late,
          extended: 102,
          lost: 0,
        ));
        expect(tracker.highest, 104);
      });

      test('extends the sequence number over the wrap', () {
        tracker.track(0xFFFE);
        expect(tracker.track(0xFFFF).extended, 0xFFFF);
        expect(tracker.track(0x10000).extended, 0x10000);
        expect(tracker.track(2), (
          arrival: MidiRtpArrival.afterLoss,
          extended: 0x10002,
          lost: 1,
        ));
        expect(tracker.track(0xFFFF), (
          arrival: MidiRtpArrival.late,
          extended: 0xFFFF,
          lost: 0,
        ));
      });
    });

    group('reset()', () {
      test('starts over', () {
        tracker
          ..track(5)
          ..reset();
        expect(tracker.highest, isNull);
        expect(tracker.track(9).arrival, MidiRtpArrival.first);
      });
    });

    group('extendBefore(sequenceNumber, extended)', () {
      test('finds the extended number at or before a packet', () {
        expect(MidiRtpSequenceTracker.extendBefore(5, 0x10005), 0x10005);
        expect(MidiRtpSequenceTracker.extendBefore(0xFFF0, 0x10005), 0xFFF0);
        expect(MidiRtpSequenceTracker.extendBefore(6, 0x10005), 0x6);
      });
    });
  });
}
