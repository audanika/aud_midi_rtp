// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import '../support/midi_rtp_equality.dart';
import 'midi_rtp_assignment.dart';
import 'midi_rtp_chapter_semantics.dart';
import 'midi_rtp_fmtp.dart';
import 'midi_rtp_fmtp_parameter.dart';
import 'midi_rtp_sending_policy.dart';
import 'midi_rtp_timestamp_mode.dart';

// #############################################################################
/// The configuration of an RTP MIDI stream: the clock rate and payload type
/// of the rtpmap line and the parameters of Appendix C that a codec uses,
/// parsed from and serialised to an SDP `a=fmtp:` line (RFC 6295 6, C,
/// Appendix D).
///
/// The parameters that only concern renderers or mpeg4-generic streams
/// (render, subrender, rinit, inline, url, cid, multimode, smf_info,
/// smf_inline, smf_url, smf_cid, chanmask, streamtype, mode, config and
/// unknown ones) are kept in order in [otherParameters].
///
/// [appleMidi] is the preset of Apple's network MIDI driver, which uses no
/// SDP: a 10 kHz clock (timestamps in units of 100 microseconds, from
/// Apple's "MIDI Network Driver Protocol"; RFC 6295 sets no default rate,
/// 6.1), payload type 97, the recovery journal in every packet, no enhanced
/// Chapter C (H = 0) and the closed-loop policy driven by the receiver
/// feedback of the session protocol.
final class MidiRtpSessionConfig {
  /// Creates a configuration.
  ///
  /// - [clockRate] the RTP timestamp units per second (rtpmap rate).
  /// - [payloadType] the RTP payload type.
  /// - [journal] whether every payload carries a recovery journal (j_sec
  ///   recj) or none (j_sec none).
  /// - [sendingPolicy] the j_update sending policy.
  /// - [assignments] the cm_used, cm_unused, ch_never, ch_default and
  ///   ch_anchor assignments in order.
  /// - [timestampMode] the tsmode; [octetPosition] (octpos), [lineRate]
  ///   (linerate, ns) and [samplingPeriod] (mperiod) refine it.
  /// - [packetTime] (rtp_ptime), [maxPacketTime] (rtp_maxptime) and
  ///   [guardTime] (guardtime) in RTP timestamp units.
  /// - [musicPort] the musicport.
  /// - [otherParameters] the remaining fmtp parameters in order.
  /// - [maxPacketSize] the largest packet the sender creates in octets,
  ///   e.g. to stay below the network MTU (RFC 6295 2.2).
  const MidiRtpSessionConfig({
    required this.clockRate,
    this.payloadType = 96,
    this.journal = true,
    this.sendingPolicy = MidiRtpSendingPolicy.closedLoop,
    this.assignments = const [],
    this.timestampMode = MidiRtpTimestampMode.comex,
    this.octetPosition,
    this.lineRate,
    this.samplingPeriod,
    this.packetTime,
    this.maxPacketTime,
    this.guardTime,
    this.musicPort,
    this.otherParameters = const [],
    this.maxPacketSize = 1472,
  }) : assert(clockRate > 0),
       assert(payloadType >= 0 && payloadType <= 0x7F),
       assert(maxPacketSize >= 64);

  // ...........................................................................
  /// Creates the configuration of [fmtp] for a stream with [clockRate].
  ///
  /// Without j_sec, the journal follows the transport: none for
  /// [reliableTransport], the recovery journal otherwise (RFC 6295 2.2).
  /// Throws a [FormatException] for values a party must not accept, such
  /// as unknown j_sec or j_update tokens (RFC 6295 C.2).
  factory MidiRtpSessionConfig.fromFmtp(
    MidiRtpFmtp fmtp, {
    required int clockRate,
    bool reliableTransport = false,
  }) {
    var journal = !reliableTransport;
    var sendingPolicy = MidiRtpSendingPolicy.closedLoop;
    var timestampMode = MidiRtpTimestampMode.comex;
    final assignments = <MidiRtpAssignment>[];
    final numbers = <String, int>{};
    String? octetPosition;
    final other = <MidiRtpFmtpParameter>[];
    for (final parameter in fmtp.parameters) {
      final value = parameter.value;
      switch (parameter.name) {
        case 'j_sec':
          journal = switch (value) {
            'recj' => true,
            'none' => false,
            _ => throw FormatException('Unknown j_sec value', value),
          };
        case 'j_update':
          sendingPolicy = MidiRtpSendingPolicy.fromToken(value);
        case 'cm_used' ||
            'cm_unused' ||
            'ch_never' ||
            'ch_default' ||
            'ch_anchor':
          assignments.add(
            MidiRtpAssignment.parse(value, parameter: parameter.name),
          );
        case 'tsmode':
          timestampMode = MidiRtpTimestampMode.fromToken(value);
        case 'octpos':
          if (value != 'first' && value != 'last') {
            throw FormatException('Unknown octpos value', value);
          }
          octetPosition = value;
        case 'linerate' ||
            'mperiod' ||
            'rtp_ptime' ||
            'rtp_maxptime' ||
            'guardtime' ||
            'musicport':
          final number = int.tryParse(value);
          if (number == null || number < 0 || number > 0xFFFFFFFF) {
            throw FormatException('Illegal ${parameter.name} value', value);
          }
          numbers[parameter.name] = number;
        default:
          other.add(parameter);
      }
    }
    return MidiRtpSessionConfig(
      clockRate: clockRate,
      payloadType: fmtp.payloadType,
      journal: journal,
      sendingPolicy: sendingPolicy,
      assignments: List.unmodifiable(assignments),
      timestampMode: timestampMode,
      octetPosition: octetPosition,
      lineRate: numbers['linerate'],
      samplingPeriod: numbers['mperiod'],
      packetTime: numbers['rtp_ptime'],
      maxPacketTime: numbers['rtp_maxptime'],
      guardTime: numbers['guardtime'],
      musicPort: numbers['musicport'],
      otherParameters: List.unmodifiable(other),
    );
  }

  // ...........................................................................
  /// Returns the fmtp line of the configuration.
  ///
  /// Parameters that hold their default are left out; [journalSection]
  /// writes j_sec even for the default recovery journal.
  MidiRtpFmtp toFmtp({bool journalSection = false}) => MidiRtpFmtp(
    payloadType: payloadType,
    parameters: [
      if (!journal || journalSection)
        MidiRtpFmtpParameter('j_sec', journal ? 'recj' : 'none'),
      if (sendingPolicy != MidiRtpSendingPolicy.closedLoop)
        MidiRtpFmtpParameter('j_update', sendingPolicy.token),
      for (final assignment in assignments)
        MidiRtpFmtpParameter(assignment.parameter, '$assignment'),
      if (timestampMode != MidiRtpTimestampMode.comex)
        MidiRtpFmtpParameter('tsmode', timestampMode.name),
      if (octetPosition != null) MidiRtpFmtpParameter('octpos', octetPosition!),
      if (lineRate != null) MidiRtpFmtpParameter('linerate', '$lineRate'),
      if (samplingPeriod != null)
        MidiRtpFmtpParameter('mperiod', '$samplingPeriod'),
      if (packetTime != null) MidiRtpFmtpParameter('rtp_ptime', '$packetTime'),
      if (maxPacketTime != null)
        MidiRtpFmtpParameter('rtp_maxptime', '$maxPacketTime'),
      if (guardTime != null) MidiRtpFmtpParameter('guardtime', '$guardTime'),
      if (musicPort != null) MidiRtpFmtpParameter('musicport', '$musicPort'),
      ...otherParameters,
    ],
  );

  // ...........................................................................
  /// Returns whether commands of the type [letter] may appear in the MIDI
  /// list (RFC 6295 C.1).
  ///
  /// The undefined system commands (J, K, Y, Z) are excluded unless
  /// assigned to cm_used; cm_used and cm_unused assignments apply in order.
  bool allowsCommand(String letter, {int? channel, int? field}) {
    var allowed = !'JKYZ'.contains(letter);
    for (final assignment in assignments) {
      if (assignment.parameter.startsWith('cm_') &&
          assignment.matches(letter, channel: channel, field: field)) {
        allowed = assignment.parameter == 'cm_used';
      }
    }
    return allowed;
  }

  /// Returns whether a System Exclusive command with the [data] octets
  /// after 0xF0 may appear in the MIDI list (RFC 6295 C.1).
  bool allowsSysEx(List<int> data) {
    var allowed = true;
    for (final assignment in assignments) {
      if (assignment.parameter.startsWith('cm_') &&
          (assignment.matchesSysEx(data) ||
              assignment.matches('X', field: data.length))) {
        allowed = assignment.parameter == 'cm_used';
      }
    }
    return allowed;
  }

  /// Returns the inclusion semantics of the chapter or subchapter [letter]
  /// on [channel] for [field] (RFC 6295 C.2.3).
  ///
  /// Subchapters of Chapter D (B, G, H, J, K, Y, Z) also follow
  /// assignments to D. For Chapter C, [field] is a controller number and
  /// matches the field values of both encodings (n and n + 128).
  MidiRtpChapterSemantics chapterSemantics(
    String letter, {
    int? channel,
    int? field,
  }) {
    var semantics = MidiRtpChapterSemantics.standard;
    for (final assignment in assignments) {
      final assigned = MidiRtpChapterSemantics.ofParameter(
        assignment.parameter,
      );
      if (assigned == null) continue;
      if (_matchesChapter(assignment, letter, channel, field)) {
        semantics = assigned;
      }
    }
    return semantics;
  }

  /// Returns the inclusion semantics of Chapter X for a System Exclusive
  /// command with the [data] octets after 0xF0 (RFC 6295 C.2.3).
  MidiRtpChapterSemantics sysExSemantics(List<int> data) {
    var semantics = MidiRtpChapterSemantics.standard;
    for (final assignment in assignments) {
      final assigned = MidiRtpChapterSemantics.ofParameter(
        assignment.parameter,
      );
      if (assigned == null) continue;
      if (assignment.matchesSysEx(data) ||
          assignment.matches('X', field: data.length)) {
        semantics = assigned;
      }
    }
    return semantics;
  }

  /// Returns whether [controller] on [channel] uses the enhanced Chapter C
  /// encoding: a ch_default or ch_anchor assignment lists it with the field
  /// value controller + 128 (RFC 6295 A.3.3, C.2.3).
  bool isEnhanced(int channel, int controller) {
    var enhanced = false;
    for (final assignment in assignments) {
      if (assignment.parameter != 'ch_default' &&
          assignment.parameter != 'ch_anchor') {
        continue;
      }
      if (!assignment.matches('C', channel: channel)) continue;
      if (assignment.fields == null) {
        enhanced = false;
      } else if (assignment.matches('C', field: controller + 128)) {
        enhanced = true;
      } else if (assignment.matches('C', field: controller)) {
        enhanced = false;
      }
    }
    return enhanced;
  }

  /// Returns whether a controller of [channel] uses the enhanced Chapter C
  /// encoding, which sets the H bit of its channel journal.
  bool usesEnhancedChapterC(int channel) => [
    for (var controller = 0; controller < 128; controller++) controller,
  ].any((controller) => isEnhanced(channel, controller));

  /// Returns a copy with the given fields replaced.
  MidiRtpSessionConfig copyWith({
    int? clockRate,
    int? payloadType,
    bool? journal,
    MidiRtpSendingPolicy? sendingPolicy,
    List<MidiRtpAssignment>? assignments,
    MidiRtpTimestampMode? timestampMode,
    String? octetPosition,
    int? lineRate,
    int? samplingPeriod,
    int? packetTime,
    int? maxPacketTime,
    int? guardTime,
    int? musicPort,
    List<MidiRtpFmtpParameter>? otherParameters,
    int? maxPacketSize,
  }) => MidiRtpSessionConfig(
    clockRate: clockRate ?? this.clockRate,
    payloadType: payloadType ?? this.payloadType,
    journal: journal ?? this.journal,
    sendingPolicy: sendingPolicy ?? this.sendingPolicy,
    assignments: assignments ?? this.assignments,
    timestampMode: timestampMode ?? this.timestampMode,
    octetPosition: octetPosition ?? this.octetPosition,
    lineRate: lineRate ?? this.lineRate,
    samplingPeriod: samplingPeriod ?? this.samplingPeriod,
    packetTime: packetTime ?? this.packetTime,
    maxPacketTime: maxPacketTime ?? this.maxPacketTime,
    guardTime: guardTime ?? this.guardTime,
    musicPort: musicPort ?? this.musicPort,
    otherParameters: otherParameters ?? this.otherParameters,
    maxPacketSize: maxPacketSize ?? this.maxPacketSize,
  );

  // ...........................................................................
  /// The RTP timestamp units per second.
  final int clockRate;

  /// The RTP payload type.
  final int payloadType;

  /// Whether every payload carries a recovery journal.
  final bool journal;

  /// The recovery journal sending policy.
  final MidiRtpSendingPolicy sendingPolicy;

  /// The subsetting and chapter inclusion assignments in order.
  final List<MidiRtpAssignment> assignments;

  /// The timestamp semantics.
  final MidiRtpTimestampMode timestampMode;

  /// The octpos value, `first` or `last`.
  final String? octetPosition;

  /// The linerate in nanoseconds per octet.
  final int? lineRate;

  /// The mperiod in RTP timestamp units.
  final int? samplingPeriod;

  /// The recommended media time of a packet (rtp_ptime).
  final int? packetTime;

  /// The largest media time of a packet (rtp_maxptime).
  final int? maxPacketTime;

  /// The largest time between two packets (guardtime).
  final int? guardTime;

  /// The musicport.
  final int? musicPort;

  /// The other fmtp parameters in order.
  final List<MidiRtpFmtpParameter> otherParameters;

  /// The largest packet the sender creates, in octets.
  final int maxPacketSize;

  // ...........................................................................
  /// The configuration of Apple's network MIDI sessions (AppleMIDI).
  static const MidiRtpSessionConfig appleMidi = MidiRtpSessionConfig(
    clockRate: 10000,
    payloadType: 97,
  );

  // ...........................................................................
  @override
  bool operator ==(Object other) =>
      other is MidiRtpSessionConfig &&
      other.clockRate == clockRate &&
      other.payloadType == payloadType &&
      other.journal == journal &&
      other.sendingPolicy == sendingPolicy &&
      MidiRtpEquality.lists(other.assignments, assignments) &&
      other.timestampMode == timestampMode &&
      other.octetPosition == octetPosition &&
      other.lineRate == lineRate &&
      other.samplingPeriod == samplingPeriod &&
      other.packetTime == packetTime &&
      other.maxPacketTime == maxPacketTime &&
      other.guardTime == guardTime &&
      other.musicPort == musicPort &&
      MidiRtpEquality.lists(other.otherParameters, otherParameters) &&
      other.maxPacketSize == maxPacketSize;

  @override
  int get hashCode => Object.hash(
    clockRate,
    payloadType,
    journal,
    sendingPolicy,
    MidiRtpEquality.hash(assignments),
    timestampMode,
    octetPosition,
    lineRate,
    samplingPeriod,
    packetTime,
    maxPacketTime,
    guardTime,
    musicPort,
    MidiRtpEquality.hash(otherParameters),
    maxPacketSize,
  );

  @override
  String toString() =>
      'MidiRtpSessionConfig(clockRate: $clockRate, '
      'maxPacketSize: $maxPacketSize, ${toFmtp()})';

  // ...........................................................................
  static bool _matchesChapter(
    MidiRtpAssignment assignment,
    String letter,
    int? channel,
    int? field,
  ) {
    final systemSubchapter = 'BGHJKYZ'.contains(letter);
    final letters = systemSubchapter ? [letter, 'D'] : [letter];
    return letters.any(
      (l) =>
          assignment.matches(l, channel: channel, field: field) ||
          (letter == 'C' &&
              field != null &&
              assignment.matches(l, channel: channel, field: field + 128)),
    );
  }
}
