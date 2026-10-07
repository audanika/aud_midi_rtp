// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../journal/midi_rtp_journal.dart';
import '../journal/midi_rtp_stream_state.dart';
import '../payload/midi_rtp_command.dart';
import '../payload/midi_rtp_packet.dart';
import '../payload/midi_rtp_sys_ex_kind.dart';
import '../session_config/midi_rtp_chapter_semantics.dart';
import '../session_config/midi_rtp_clock.dart';
import '../session_config/midi_rtp_session_config.dart';
import 'midi_rtp_arrival.dart';
import 'midi_rtp_journal_repair.dart';
import 'midi_rtp_sequence_tracker.dart';

// #############################################################################
/// The receiving side of an RTP MIDI stream: decodes packets into timed
/// MIDI messages and repairs every loss from the recovery journal (RFC 6295
/// 3, 4; RFC 4696 6, 7).
///
/// The receiver detects every sequence number break: packets after a gap
/// end a loss event, whose repair commands come before the packet's own
/// commands; late and duplicate packets are ignored. It validates the
/// checkpoint of each loss: an uncovered loss also ends the notes the
/// journal does not confirm. Every loss is reported to [onIssue] as
/// [MidiDiagnosticKind.networkLoss] and counted. [feedbackSequenceNumber]
/// is the value to send back to the sender, e.g. in an AppleMIDI RS
/// command, for the closed-loop policy. It creates no sockets.
final class MidiRtpReceiver {
  /// Creates a receiver.
  ///
  /// - [config] the session configuration; AppleMIDI by default.
  /// - [clock] maps RTP timestamps to times; by default timestamp zero is
  ///   time zero at the clock rate of [config].
  /// - [maxSysExLength] the longest System Exclusive command delivered, in
  ///   data octets.
  /// - [onIssue] receives losses and dropped data.
  MidiRtpReceiver({
    this.config = MidiRtpSessionConfig.appleMidi,
    MidiRtpClock? clock,
    this.maxSysExLength = 1 << 20,
    this.onIssue,
  }) : clock = clock ?? MidiRtpClock(rate: config.clockRate) {
    _restart();
  }

  // ...........................................................................
  /// Decodes the packet [bytes] and returns its messages with their times:
  /// repair commands first, then the commands of the packet.
  ///
  /// Malformed packets are reported as [MidiDiagnosticKind.invalidData] and
  /// count as lost when the next packet arrives.
  List<MidiTimedMessage> receive(List<int> bytes) {
    final MidiRtpPacket packet;
    try {
      packet = MidiRtpPacket.decode(bytes);
    } on FormatException catch (e) {
      _discard(
        MidiDiagnosticKind.invalidData,
        'Malformed packet: ${e.message}',
      );
      return const [];
    }
    return receivePacket(packet);
  }

  /// Returns the messages of the decoded [packet] (see [receive]).
  List<MidiTimedMessage> receivePacket(MidiRtpPacket packet) {
    final header = packet.header;
    if (header.payloadType != config.payloadType) {
      _discard(
        MidiDiagnosticKind.invalidData,
        'Payload type ${header.payloadType} is not ${config.payloadType}',
      );
      return const [];
    }
    final out = <MidiTimedMessage>[];
    final time = clock.toTime(header.timestamp, near: _lastTime);
    if (_ssrc != null && _ssrc != header.ssrc) {
      onIssue?.call(
        MidiDiagnosticKind.networkLoss,
        'The synchronization source changed to ${header.ssrc}',
      );
      out.addAll(close(time: time));
    }
    _ssrc = header.ssrc;
    final highest = _tracker.highest;
    final track = _tracker.track(header.sequenceNumber);
    if (!track.arrival.isAccepted) {
      _discard(
        null,
        'Packet ${header.sequenceNumber} arrived ${track.arrival.name}',
      );
      return out;
    }
    _received++;
    _lastTime = time;
    final seq = track.extended;
    if (track.arrival == MidiRtpArrival.afterLoss) {
      _lost += track.lost;
    }
    final journal = packet.payload.journal;
    if (track.arrival != MidiRtpArrival.next) {
      final repairs = journal == null
          ? _unjournaled(track.lost, seq)
          : _repairFrom(journal, track, highest);
      _repairs += repairs.length;
      out.addAll([for (final m in repairs) (message: m, time: time)]);
    }
    out.addAll(_commands(packet, seq, time));
    return out;
  }

  /// Returns the commands that leave no indefinite artifact when the stream
  /// ends at [time]: NoteOffs for the sounding notes and pedal releases
  /// (RFC 6295 4); the receiver then expects a new stream.
  List<MidiTimedMessage> close({MidiTime? time}) {
    final at = time ?? _lastTime;
    final silence = _repair.silence(seq: _tracker.highest ?? 0);
    _restart();
    return [for (final m in silence) (message: m, time: at)];
  }

  // ...........................................................................
  /// The session configuration.
  final MidiRtpSessionConfig config;

  /// Maps RTP timestamps to times.
  final MidiRtpClock clock;

  /// The longest System Exclusive command delivered, in data octets.
  final int maxSysExLength;

  /// Receives losses and dropped data.
  final MidiIssueCallback? onIssue;

  /// The receiver's model of the stream: the state after the packets and
  /// repairs so far.
  MidiRtpStreamState get model => _model;

  /// The synchronization source of the stream, or null before the first
  /// packet.
  int? get ssrc => _ssrc;

  /// The highest 16-bit sequence number received: the receiver feedback
  /// for the sender's closed-loop policy, or null before the first packet.
  int? get feedbackSequenceNumber =>
      _tracker.highest == null ? null : _tracker.highest! & 0xFFFF;

  /// The highest extended sequence number received, or null.
  int? get highestSequenceNumber => _tracker.highest;

  /// The number of packets processed.
  int get packetsReceived => _received;

  /// The number of packets lost in sequence number gaps.
  int get packetsLost => _lost;

  /// The number of lost packets whose loss the journal covered.
  int get packetsRecovered => _recovered;

  /// The number of repair commands the journals produced.
  int get journalRepairs => _repairs;

  /// The number of packets ignored: late, duplicate, malformed or of a
  /// foreign payload type.
  int get packetsDiscarded => _discarded;

  /// The packet statistics as the network model of the family reports
  /// them.
  MidiNetworkLossStats get lossStats => MidiNetworkLossStats(
    packetsReceived: _received,
    packetsLost: _lost,
    packetsRecovered: _recovered,
    journalRepairs: _repairs,
  );

  // ...........................................................................
  late MidiRtpStreamState _model;
  late MidiRtpJournalRepair _repair;
  final MidiRtpSequenceTracker _tracker = MidiRtpSequenceTracker();
  int? _ssrc;
  MidiTime _lastTime = MidiTime.zero;
  MidiTime? _sysExTime;
  int _received = 0;
  int _lost = 0;
  int _recovered = 0;
  int _repairs = 0;
  int _discarded = 0;

  void _restart() {
    _model = MidiRtpStreamState(
      countsSysEx: (data) =>
          config.sysExSemantics(data) != MidiRtpChapterSemantics.never,
    );
    _repair = MidiRtpJournalRepair(model: _model, onIssue: onIssue);
    _tracker.reset();
    _sysExTime = null;
  }

  void _discard(MidiDiagnosticKind? kind, String cause) {
    _discarded++;
    if (kind != null) onIssue?.call(kind, cause);
  }

  List<MidiMessage> _repairFrom(
    MidiRtpJournal journal,
    ({MidiRtpArrival arrival, int extended, int lost}) track,
    int? highest,
  ) {
    final seq = track.extended;
    final checkpoint = MidiRtpSequenceTracker.extendBefore(
      journal.checkpoint,
      seq,
    );
    final covered = highest == null || checkpoint <= highest + 1;
    if (track.lost > 0) {
      if (covered) _recovered += track.lost;
      onIssue?.call(
        MidiDiagnosticKind.networkLoss,
        'Lost ${track.lost} packet(s) before ${seq & 0xFFFF}, '
        '${covered ? 'recovered from the journal' : 'not covered by the '
                  'journal (checkpoint ${journal.checkpoint})'}',
      );
    }
    return _repair.repair(
      journal,
      seq: seq,
      checkpoint: checkpoint,
      singleLoss: track.lost == 1,
      covered: covered,
    );
  }

  List<MidiMessage> _unjournaled(int lost, int seq) {
    if (lost == 0) return const [];
    onIssue?.call(
      MidiDiagnosticKind.networkLoss,
      'Lost $lost packet(s) before ${seq & 0xFFFF} without a journal',
    );
    return config.journal ? _repair.silence(seq: seq) : const [];
  }

  List<MidiTimedMessage> _commands(
    MidiRtpPacket packet,
    int seq,
    MidiTime time,
  ) {
    final out = <MidiTimedMessage>[];
    var timestamp = packet.header.timestamp;
    for (final command in packet.payload.commands) {
      timestamp = (timestamp + command.deltaTime) & 0xFFFFFFFF;
      final at = clock.toTime(timestamp, near: time);
      switch (command) {
        case MidiRtpMessageCommand(:final message):
          _model.apply(message, seq: seq, time: at);
          out.add((message: message, time: at));
        case MidiRtpSysExCommand():
          final message = _sysEx(command, seq, at);
          if (message != null) out.add(message);
        case MidiRtpUndefinedCommand(:final status, :final data):
          _model.applyUndefined(status, data, seq: seq);
          if (data.length > 2) {
            onIssue?.call(
              MidiDiagnosticKind.untranslatable,
              'Undefined command 0x${status.toRadixString(16)} with '
              '${data.length} data octets has no message form',
            );
          } else {
            out.add((
              message: MidiRtpJournalRepair.undefinedMessage(status, data),
              time: at,
            ));
          }
        case MidiRtpEmptyCommand():
          break;
      }
    }
    return out;
  }

  MidiTimedMessage? _sysEx(MidiRtpSysExCommand command, int seq, MidiTime at) {
    final kind = command.kind;
    final system = _model.system;
    if (kind.startsCommand) {
      _sysExTime = at;
    } else if (system.unfinishedSysEx == null) {
      onIssue?.call(
        MidiDiagnosticKind.sysExIncomplete,
        'A System Exclusive segment without its start was dropped',
      );
      return null;
    }
    final completed = _model.applySysEx(
      kind,
      command.data,
      droppedF7: command.droppedF7,
      seq: seq,
    );
    final unfinished = system.unfinishedSysEx;
    if (unfinished != null && unfinished.data.length > maxSysExLength) {
      _model.applySysEx(MidiRtpSysExKind.cancel, const [], seq: seq);
      onIssue?.call(
        MidiDiagnosticKind.sysExTooLong,
        'A System Exclusive command exceeded $maxSysExLength octets',
      );
      return null;
    }
    if (completed == null) return null;
    if (completed.length > maxSysExLength) {
      onIssue?.call(
        MidiDiagnosticKind.sysExTooLong,
        'A System Exclusive command exceeded $maxSysExLength octets',
      );
      return null;
    }
    final time = _sysExTime ?? at;
    _sysExTime = null;
    return (message: MidiSysEx(completed), time: time);
  }
}
