// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

// #############################################################################
/// Converts between the package clock ([MidiTime]) and the 32-bit RTP
/// timestamps of a stream (RFC 3550 5.1, RFC 6295 2.1).
///
/// The clock pairs a base [time] with the RTP [timestamp] it corresponds to;
/// the session layer chooses both, e.g. from the AppleMIDI clock
/// synchronisation. Timestamps count [rate] units per second and wrap at
/// 2^32.
final class MidiRtpClock {
  /// Creates a clock with [rate] timestamp units per second whose
  /// [timestamp] corresponds to [time].
  const MidiRtpClock({
    required this.rate,
    this.time = MidiTime.zero,
    this.timestamp = 0,
  }) : assert(rate > 0),
       assert(timestamp >= 0 && timestamp <= 0xFFFFFFFF);

  // ...........................................................................
  /// Returns the RTP timestamp of [time], rounded to the nearest unit.
  int toTimestamp(MidiTime time) =>
      (timestamp + ticks(time.difference(this.time))) & 0xFFFFFFFF;

  /// Returns the time of the RTP [timestamp].
  ///
  /// Of all times whose timestamp wraps to [timestamp], the one nearest to
  /// [near] is chosen; [near] defaults to the base time.
  MidiTime toTime(int timestamp, {MidiTime? near}) {
    final reference = near ?? time;
    final delta =
        ((timestamp - toTimestamp(reference) + 0x80000000) & 0xFFFFFFFF) -
        0x80000000;
    return reference + duration(delta);
  }

  /// Returns [duration] in timestamp units, rounded to the nearest unit.
  int ticks(Duration duration) =>
      (duration.inMicroseconds * rate / Duration.microsecondsPerSecond).round();

  /// Returns the duration of [ticks] timestamp units, rounded to the
  /// nearest microsecond.
  Duration duration(int ticks) => Duration(
    microseconds: (ticks * Duration.microsecondsPerSecond / rate).round(),
  );

  /// Returns a copy with the given fields replaced.
  MidiRtpClock copyWith({int? rate, MidiTime? time, int? timestamp}) =>
      MidiRtpClock(
        rate: rate ?? this.rate,
        time: time ?? this.time,
        timestamp: timestamp ?? this.timestamp,
      );

  // ...........................................................................
  /// The timestamp units per second, the clock rate of the stream.
  final int rate;

  /// The base time.
  final MidiTime time;

  /// The RTP timestamp of the base time.
  final int timestamp;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpClock &&
      other.rate == rate &&
      other.time == time &&
      other.timestamp == timestamp;

  @override
  int get hashCode => Object.hash(rate, time, timestamp);

  @override
  String toString() =>
      'MidiRtpClock(rate: $rate, time: ${time.microseconds}, '
      'timestamp: $timestamp)';
}
