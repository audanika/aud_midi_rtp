// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// One assignment to a stream subsetting parameter (cm_used, cm_unused,
/// RFC 6295 C.1) or a chapter inclusion parameter (ch_never, ch_default,
/// ch_anchor, RFC 6295 C.2.3), in the syntax of Appendix D:
/// `[channel list]letters[field list]` or `__h-list_h-list__` for a class
/// of System Exclusive commands.
///
/// Lists are dot-separated numbers and dash-separated ranges, e.g. `0-5.9`.
/// The letters name command types or chapters; letters the memo does not
/// define are kept for serialisation and never match.
final class MidiRtpAssignment {
  /// Creates an assignment to [parameter].
  ///
  /// - [channels] the channel list as ranges, or null for all channels.
  /// - [letters] the command type or chapter letters.
  /// - [fields] the field list as ranges, or null for all fields.
  /// - [sysEx] the h-lists of a System Exclusive class: per data octet the
  ///   permitted ranges; [letters] is empty then.
  MidiRtpAssignment({
    required this.parameter,
    Iterable<(int, int)>? channels,
    this.letters = '',
    Iterable<(int, int)>? fields,
    Iterable<Iterable<(int, int)>>? sysEx,
  }) : channels = channels == null ? null : List.unmodifiable(channels),
       fields = fields == null ? null : List.unmodifiable(fields),
       sysEx = sysEx == null
           ? null
           : List.unmodifiable([
               for (final octet in sysEx) List<(int, int)>.unmodifiable(octet),
             ]);

  // ...........................................................................
  /// Parses the [value] assigned to [parameter].
  ///
  /// Throws a [FormatException] when the value does not follow the syntax.
  factory MidiRtpAssignment.parse(String value, {required String parameter}) {
    final text = value.trim();
    if (text.startsWith('__')) {
      if (text.length < 5 || !text.endsWith('__')) {
        throw FormatException('Illegal SysEx class', value);
      }
      return MidiRtpAssignment(
        parameter: parameter,
        sysEx: text
            .substring(2, text.length - 2)
            .split('_')
            .map((octet) => _parseList(octet, radix: 16, source: value)),
      );
    }
    final match = RegExp(r'^([0-9.\-]*)([A-Z]+)([0-9.\-]*)$').firstMatch(text);
    if (match == null) {
      throw FormatException('Illegal assignment', value);
    }
    final channels = match.group(1)!;
    final fields = match.group(3)!;
    return MidiRtpAssignment(
      parameter: parameter,
      channels: channels.isEmpty
          ? null
          : _parseList(channels, radix: 10, source: value),
      letters: match.group(2)!,
      fields: fields.isEmpty
          ? null
          : _parseList(fields, radix: 10, source: value),
    );
  }

  // ...........................................................................
  /// Returns whether the assignment covers [letter] on [channel] for
  /// [field]; a null [channel] or [field] matches every list.
  bool matches(String letter, {int? channel, int? field}) =>
      letters.contains(letter) &&
      (channel == null || channels == null || _contains(channels!, channel)) &&
      (field == null || fields == null || _contains(fields!, field));

  /// Returns whether the System Exclusive class of the assignment covers a
  /// command with the [data] octets after 0xF0.
  bool matchesSysEx(List<int> data) {
    final pattern = sysEx;
    if (pattern == null || data.length < pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (!_contains(pattern[i], data[i])) return false;
    }
    return true;
  }

  /// Returns whether the channel list holds [number], e.g. the special
  /// digits of the X command type or the J, K, Q, Y and Z chapters.
  bool hasChannel(int number) =>
      channels != null && _contains(channels!, number);

  // ...........................................................................
  /// The parameter the value is assigned to, e.g. `ch_never`.
  final String parameter;

  /// The channel list; null for all channels; cannot be modified.
  final List<(int, int)>? channels;

  /// The command type or chapter letters.
  final String letters;

  /// The field list; null for all fields; cannot be modified.
  final List<(int, int)>? fields;

  /// The h-lists of a System Exclusive class; cannot be modified.
  final List<List<(int, int)>>? sysEx;

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpAssignment &&
      other.parameter == parameter &&
      other.toString() == toString();

  @override
  int get hashCode => Object.hash(parameter, toString());

  /// Returns the value as it appears on an fmtp line, e.g. `1-3C7.64`.
  @override
  String toString() {
    if (sysEx != null) {
      return '__${sysEx!.map((octet) => _list(octet, radix: 16)).join('_')}__';
    }
    return '${channels == null ? '' : _list(channels!, radix: 10)}$letters'
        '${fields == null ? '' : _list(fields!, radix: 10)}';
  }

  // ...........................................................................
  static List<(int, int)> _parseList(
    String text, {
    required int radix,
    required String source,
  }) => text.split('.').map((element) {
    final bounds = element.split('-');
    final from = int.tryParse(bounds.first, radix: radix);
    final to = int.tryParse(bounds.last, radix: radix);
    if (bounds.length > 2 || from == null || to == null || from > to) {
      throw FormatException('Illegal list element "$element"', source);
    }
    return (from, to);
  }).toList();

  static String _list(List<(int, int)> ranges, {required int radix}) => ranges
      .map((range) {
        String text(int n) => radix == 16
            ? n.toRadixString(16).toUpperCase().padLeft(2, '0')
            : '$n';
        return range.$1 == range.$2
            ? text(range.$1)
            : '${text(range.$1)}-${text(range.$2)}';
      })
      .join('.');

  static bool _contains(List<(int, int)> ranges, int number) =>
      ranges.any((range) => number >= range.$1 && number <= range.$2);
}
