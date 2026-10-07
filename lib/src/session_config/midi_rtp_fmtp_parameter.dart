// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// One `name=value` assignment of an SDP `a=fmtp:` line of an RTP MIDI
/// stream (RFC 6295 6.3, Appendix D).
///
/// Values of the cid, inline, url, smf_cid, smf_inline and smf_url
/// parameters are double-quoted strings; [quoted] keeps the quotes for any
/// parameter so that unknown parameters round-trip unchanged.
final class MidiRtpFmtpParameter {
  /// Creates a parameter [name] with [value]; [quoted] writes the value in
  /// double quotes.
  const MidiRtpFmtpParameter(this.name, this.value, {this.quoted = false});

  // ...........................................................................
  /// Parses one `name=value` assignment.
  ///
  /// Throws a [FormatException] when the `=` is missing or the name is
  /// empty.
  factory MidiRtpFmtpParameter.parse(String assignment) {
    final text = assignment.trim();
    final equals = text.indexOf('=');
    if (equals <= 0) {
      throw FormatException('Not a name=value assignment', assignment);
    }
    final name = text.substring(0, equals).trim();
    var value = text.substring(equals + 1).trim();
    final quoted =
        value.length >= 2 && value.startsWith('"') && value.endsWith('"');
    if (quoted) value = value.substring(1, value.length - 1);
    return MidiRtpFmtpParameter(name, value, quoted: quoted);
  }

  // ...........................................................................
  /// The parameter name, e.g. `j_update`.
  final String name;

  /// The value without quotes.
  final String value;

  /// Whether the value is written in double quotes.
  final bool quoted;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpFmtpParameter &&
      other.name == name &&
      other.value == value &&
      other.quoted == quoted;

  @override
  int get hashCode => Object.hash(name, value, quoted);

  /// Returns the assignment as it appears on an fmtp line.
  @override
  String toString() => quoted ? '$name="$value"' : '$name=$value';
}
