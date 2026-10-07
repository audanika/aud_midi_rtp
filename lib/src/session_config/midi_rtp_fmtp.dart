// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import '../support/midi_rtp_equality.dart';
import 'midi_rtp_fmtp_parameter.dart';

// #############################################################################
/// An SDP `a=fmtp:` attribute line of an RTP MIDI payload type: the payload
/// type and its parameters in order (RFC 6295 Appendix D, RFC 4566).
///
/// The order matters: assignments to cm_used, cm_unused and the chapter
/// inclusion parameters accumulate, and renderer parameters belong to the
/// render parameter before them (RFC 6295 C.1, C.2.3, C.6).
final class MidiRtpFmtp {
  /// Creates an fmtp line for [payloadType] with [parameters].
  MidiRtpFmtp({
    required this.payloadType,
    Iterable<MidiRtpFmtpParameter> parameters = const [],
  }) : parameters = List.unmodifiable(parameters) {
    assert(payloadType >= 0 && payloadType <= 0x7F);
  }

  // ...........................................................................
  /// Parses an `a=fmtp:<payload type> name=value; name=value` line.
  ///
  /// Semicolons inside double quotes do not separate parameters; extra
  /// whitespace and an empty last parameter are accepted. Throws a
  /// [FormatException] when the line is malformed.
  factory MidiRtpFmtp.parse(String line) {
    final text = line.trim();
    const prefix = 'a=fmtp:';
    if (!text.startsWith(prefix)) {
      throw FormatException('Not an fmtp line', line);
    }
    final rest = text.substring(prefix.length);
    final space = rest.indexOf(RegExp(r'\s'));
    final payloadType = int.tryParse(
      space < 0 ? rest : rest.substring(0, space),
    );
    if (payloadType == null || payloadType < 0 || payloadType > 0x7F) {
      throw FormatException('Illegal payload type', line);
    }
    return MidiRtpFmtp(
      payloadType: payloadType,
      parameters: space < 0
          ? const []
          : _split(rest.substring(space)).map(MidiRtpFmtpParameter.parse),
    );
  }

  // ...........................................................................
  /// Returns the parameters named [name] in order.
  List<MidiRtpFmtpParameter> all(String name) =>
      parameters.where((p) => p.name == name).toList();

  // ...........................................................................
  /// The RTP payload type the line configures.
  final int payloadType;

  /// The parameters in order; cannot be modified.
  final List<MidiRtpFmtpParameter> parameters;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpFmtp &&
      other.payloadType == payloadType &&
      MidiRtpEquality.lists(other.parameters, parameters);

  @override
  int get hashCode =>
      Object.hash(payloadType, MidiRtpEquality.hash(parameters));

  /// Returns the attribute line, e.g. `a=fmtp:96 j_update=anchor`.
  @override
  String toString() => parameters.isEmpty
      ? 'a=fmtp:$payloadType'
      : 'a=fmtp:$payloadType ${parameters.join('; ')}';

  // ...........................................................................
  static List<String> _split(String text) {
    final parts = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (final char in text.split('')) {
      if (char == '"') quoted = !quoted;
      if (char == ';' && !quoted) {
        parts.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    parts.add(current.toString());
    return parts.where((p) => p.trim().isNotEmpty).toList();
  }
}
