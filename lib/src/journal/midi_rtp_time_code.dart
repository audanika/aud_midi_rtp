// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// A MIDI Time Code tape position as System Chapter F codes it: hours,
/// minutes, seconds, frames and the frame rate (RFC 6295 B.4, MIDI 1.0
/// Detailed Specification, MIDI Time Code).
///
/// The position converts between the eight Quarter Frame nibbles, the four
/// data octets of a Full Frame message and the 32-bit COMPLETE and PARTIAL
/// fields of Chapter F (Figures B.4.2 and B.4.3).
final class MidiRtpTimeCode {
  /// Creates a position; [rate] is 0 for 24, 1 for 25, 2 for 29.97 drop
  /// frame and 3 for 30 frames per second.
  const MidiRtpTimeCode({
    this.hours = 0,
    this.minutes = 0,
    this.seconds = 0,
    this.frames = 0,
    this.rate = 0,
  }) : assert(hours >= 0 && hours <= 0x1F),
       assert(minutes >= 0 && minutes <= 0x3F),
       assert(seconds >= 0 && seconds <= 0x3F),
       assert(frames >= 0 && frames <= 0x1F),
       assert(rate >= 0 && rate <= 3);

  // ...........................................................................
  /// Creates a position from the data nibbles of the Quarter Frame messages
  /// of message types 0 to 7; reserved bits are ignored.
  factory MidiRtpTimeCode.fromNibbles(List<int> nibbles) => MidiRtpTimeCode(
    frames: (nibbles[1] & 0x01) << 4 | nibbles[0],
    seconds: (nibbles[3] & 0x03) << 4 | nibbles[2],
    minutes: (nibbles[5] & 0x03) << 4 | nibbles[4],
    hours: (nibbles[7] & 0x01) << 4 | nibbles[6],
    rate: (nibbles[7] >> 1) & 0x03,
  );

  /// Creates a position from the hr, mn, sc and fr octets of a Full Frame
  /// message (F0 7F cc 01 01 hr mn sc fr F7).
  factory MidiRtpTimeCode.fromFullFrame(List<int> octets) => MidiRtpTimeCode(
    hours: octets[0] & 0x1F,
    rate: (octets[0] >> 5) & 0x03,
    minutes: octets[1] & 0x3F,
    seconds: octets[2] & 0x3F,
    frames: octets[3] & 0x1F,
  );

  /// Creates a position from a 32-bit Chapter F COMPLETE field; [nibbles]
  /// tells the format: Quarter Frame nibbles (Q = 1) or Full Frame octets
  /// (Q = 0).
  factory MidiRtpTimeCode.fromField(int field, {required bool nibbles}) =>
      nibbles
      ? MidiRtpTimeCode.fromNibbles([
          for (var i = 7; i >= 0; i--) (field >> (4 * i)) & 0x0F,
        ])
      : MidiRtpTimeCode.fromFullFrame([
          for (var i = 3; i >= 0; i--) (field >> (8 * i)) & 0xFF,
        ]);

  // ...........................................................................
  /// Returns the position [count] frames later, counting with the frame
  /// rate and skipping the dropped frame numbers of 29.97 drop frame.
  MidiRtpTimeCode advance(int count) {
    var hours = this.hours;
    var minutes = this.minutes;
    var seconds = this.seconds;
    var frames = this.frames;
    for (var i = 0; i < count; i++) {
      frames++;
      if (frames >= framesPerSecond) {
        frames = 0;
        seconds++;
      }
      if (seconds >= 60) {
        seconds = 0;
        minutes++;
      }
      if (minutes >= 60) {
        minutes = 0;
        hours++;
      }
      if (hours >= 24) hours = 0;
      if (rate == 2 && seconds == 0 && frames < 2 && minutes % 10 != 0) {
        frames = 2;
      }
    }
    return MidiRtpTimeCode(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      frames: frames,
      rate: rate,
    );
  }

  // ...........................................................................
  /// Returns the data nibbles of the Quarter Frame messages of message
  /// types 0 to 7.
  List<int> toNibbles() => [
    frames & 0x0F,
    frames >> 4,
    seconds & 0x0F,
    seconds >> 4,
    minutes & 0x0F,
    minutes >> 4,
    hours & 0x0F,
    rate << 1 | hours >> 4,
  ];

  /// Returns the hr, mn, sc and fr octets of a Full Frame message.
  List<int> toFullFrame() => [rate << 5 | hours, minutes, seconds, frames];

  /// Returns the 32-bit Chapter F field in the format [nibbles] selects.
  int toField({required bool nibbles}) => nibbles
      ? toNibbles().fold(0, (field, nibble) => field << 4 | nibble)
      : toFullFrame().fold(0, (field, octet) => field << 8 | octet);

  // ...........................................................................
  /// The hours.
  final int hours;

  /// The minutes.
  final int minutes;

  /// The seconds.
  final int seconds;

  /// The frames.
  final int frames;

  /// The frame rate code.
  final int rate;

  /// The number of frame numbers per second of the rate.
  int get framesPerSecond => const [24, 25, 30, 30][rate];

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpTimeCode &&
      other.hours == hours &&
      other.minutes == minutes &&
      other.seconds == seconds &&
      other.frames == frames &&
      other.rate == rate;

  @override
  int get hashCode => Object.hash(hours, minutes, seconds, frames, rate);

  @override
  String toString() =>
      'MidiRtpTimeCode($hours:$minutes:$seconds:$frames, rate: $rate)';
}
