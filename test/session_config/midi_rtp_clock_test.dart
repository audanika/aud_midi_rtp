// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_rtp/aud_midi_rtp.dart';
import 'package:aud_midi_standard/aud_midi_standard.dart';
import 'package:test/test.dart';

void main() {
  group('MidiRtpClock', () {
    const clock = MidiRtpClock(
      rate: 10000,
      time: MidiTime(1000000),
      timestamp: 500,
    );

    group('toTimestamp(time)', () {
      test('counts units from the base', () {
        expect(clock.toTimestamp(const MidiTime(1000000)), 500);
        expect(clock.toTimestamp(const MidiTime(1000100)), 501);
        expect(clock.toTimestamp(const MidiTime(1000149)), 501);
        expect(clock.toTimestamp(const MidiTime(1000150)), 502);
        expect(clock.toTimestamp(const MidiTime(2000000)), 10500);
      });

      test('wraps at 2^32', () {
        expect(clock.toTimestamp(const MidiTime(900000)), 0xFFFFFFFF - 499);
        const late = MidiRtpClock(rate: 1000000, timestamp: 0xFFFFFFFF);
        expect(late.toTimestamp(const MidiTime(2)), 1);
      });
    });

    group('toTime(timestamp, near)', () {
      test('converts timestamps near the base', () {
        expect(clock.toTime(10500), const MidiTime(2000000));
        expect(clock.toTime(0xFFFFFFFF - 499), const MidiTime(900000));
      });

      test('chooses the wrap nearest to near', () {
        const fast = MidiRtpClock(rate: 1000000);
        final far = const MidiTime(0) + const Duration(hours: 2);
        final timestamp = fast.toTimestamp(far);
        expect(fast.toTime(timestamp, near: far), far);
        expect(fast.toTime(timestamp), isNot(far));
      });
    });

    group('ticks(duration) and duration(ticks)', () {
      test('convert with rounding', () {
        expect(clock.ticks(const Duration(milliseconds: 1)), 10);
        expect(clock.ticks(const Duration(microseconds: -150)), -2);
        expect(clock.duration(3), const Duration(microseconds: 300));
        const odd = MidiRtpClock(rate: 44100);
        expect(odd.duration(1), const Duration(microseconds: 23));
      });
    });

    group('copyWith()', () {
      test('replaces the given fields', () {
        expect(clock.copyWith(), clock);
        expect(
          clock.copyWith(rate: 1, time: MidiTime.zero, timestamp: 0),
          const MidiRtpClock(rate: 1),
        );
      });
    });

    group('==, hashCode, toString', () {
      test('compare by value', () {
        const same = MidiRtpClock(
          rate: 10000,
          time: MidiTime(1000000),
          timestamp: 500,
        );
        expect(clock, same);
        expect(clock.hashCode, same.hashCode);
        expect(clock == clock.copyWith(rate: 1), isFalse);
        expect(clock == clock.copyWith(time: MidiTime.zero), isFalse);
        expect(clock == clock.copyWith(timestamp: 1), isFalse);
        expect(
          clock.toString(),
          'MidiRtpClock(rate: 10000, time: 1000000, timestamp: 500)',
        );
      });
    });
  });
}
