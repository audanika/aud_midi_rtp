// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:math';

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../journal/midi_rtp_journal.dart';
import '../journal/midi_rtp_stream_state.dart';
import '../payload/midi_rtp_command.dart';
import '../payload/midi_rtp_command_section.dart';
import '../payload/midi_rtp_delta_time.dart';
import '../payload/midi_rtp_header.dart';
import '../payload/midi_rtp_packet.dart';
import '../payload/midi_rtp_payload.dart';
import '../payload/midi_rtp_sys_ex_kind.dart';
import '../session_config/midi_rtp_chapter_semantics.dart';
import '../session_config/midi_rtp_clock.dart';
import '../session_config/midi_rtp_sending_policy.dart';
import '../session_config/midi_rtp_session_config.dart';
import 'midi_rtp_journal_builder.dart';

// #############################################################################
/// The sending side of an RTP MIDI stream: turns timed MIDI 1.0 messages
/// into RTP MIDI packets with a recovery journal in each (RFC 6295 2 to 5,
/// C.2; RFC 4696 4, 5).
///
/// The sender keeps the session history, chooses the checkpoint of every
/// journal by the sending policy of the configuration and trims the
/// history when the receiver acknowledges packets (closed-loop policy,
/// RFC 6295 C.2.2.2: AppleMIDI's receiver feedback provides the
/// acknowledgements). Packets stay below the configured maximum size;
/// System Exclusive commands that do not fit are segmented across packets
/// (RFC 6295 3.2). It creates no sockets: the caller sends the packets.
///
/// ```dart
/// final sender = MidiRtpSender(ssrc: 0x1234, sequenceNumber: 100);
/// final packets = sender.send([
///   (message: const MidiNoteOn(channel: 0, note: 60, velocity: 90),
///    time: MidiTime(1000)),
/// ]);
/// // send packets[i].toBytes(); on feedback:
/// sender.acknowledge(100);
/// ```
final class MidiRtpSender {
  /// Creates a sender.
  ///
  /// - [config] the session configuration; AppleMIDI by default.
  /// - [ssrc] the synchronization source of the stream.
  /// - [sequenceNumber] the 16-bit sequence number of the first packet,
  ///   which should be random (RFC 3550 5.1).
  /// - [clock] maps message times to RTP timestamps; by default time zero
  ///   is timestamp zero at the clock rate of [config].
  /// - [recentNoteOn] the age up to which recovered NoteOns are
  ///   recommended for playing (Y bit).
  /// - [openLoopWindow] the number of packets the journal covers under the
  ///   open-loop policy.
  /// - [maxJournalLength] the largest journal in octets; when a receiver's
  ///   feedback stays away so long that the journal grows beyond it, the
  ///   sender gives up the receiver's history like an early SSRC time-out
  ///   (RFC 6295 C.2.2.2) and reports a [MidiDiagnosticKind.networkLoss].
  /// - [onIssue] receives messages the stream cannot carry and journal
  ///   time-outs.
  MidiRtpSender({
    this.config = MidiRtpSessionConfig.appleMidi,
    required this.ssrc,
    int sequenceNumber = 0,
    MidiRtpClock? clock,
    Duration recentNoteOn = const Duration(milliseconds: 100),
    this.openLoopWindow = 64,
    this.maxJournalLength,
    this.onIssue,
  }) : assert(ssrc >= 0 && ssrc <= 0xFFFFFFFF),
       assert(sequenceNumber >= 0 && sequenceNumber <= 0xFFFF),
       clock = clock ?? MidiRtpClock(rate: config.clockRate),
       _next = sequenceNumber,
       _first = sequenceNumber,
       _builder = MidiRtpJournalBuilder(
         config: config,
         recentNoteOn: recentNoteOn,
         onIssue: onIssue,
       ),
       history = MidiRtpStreamState(
         isEnhanced: config.isEnhanced,
         countsSysEx: (data) =>
             config.sysExSemantics(data) != MidiRtpChapterSemantics.never,
       );

  // ...........................................................................
  /// Encodes [messages] into packets, in the order given.
  ///
  /// Each packet starts at the RTP timestamp of its first command (Z = 0);
  /// times that go backwards are clamped to the previous time. Messages
  /// without a MIDI 1.0 byte form and command types the configuration
  /// excludes (RFC 6295 C.1) are reported to [onIssue] and skipped.
  /// Returns no packet when nothing is left to send.
  List<MidiRtpPacket> send(Iterable<MidiTimedMessage> messages) {
    final queue = <_Pending>[];
    for (final timed in messages) {
      if (!_accepts(timed.message)) continue;
      final time = timed.time.isBefore(_lastTime) ? _lastTime : timed.time;
      _lastTime = time;
      queue.add(_Pending(timed.message, time, clock.toTimestamp(time)));
    }
    final packets = <MidiRtpPacket>[];
    var index = 0;
    var offset = 0;
    while (index < queue.length) {
      final fill = _fill(queue, index, offset);
      packets.add(fill.packet);
      index = fill.index;
      offset = fill.offset;
    }
    return packets;
  }

  /// Returns a packet with an empty MIDI list at [time] that carries the
  /// current journal, e.g. a guard or keep-alive packet (RFC 4696 4.2).
  MidiRtpPacket guard({required MidiTime time}) {
    if (time.isAfter(_lastTime)) _lastTime = time;
    final seq = _next;
    return _packet(
      seq,
      clock.toTimestamp(_lastTime),
      const [],
      _journal(seq, _lastTime),
    );
  }

  /// Applies receiver feedback: the receiver has seen every packet up to
  /// the 16-bit [sequenceNumber], e.g. from an AppleMIDI RS command.
  ///
  /// The number is extended to the sender's rollover count; older
  /// acknowledgements are ignored. Under the closed-loop policy the next
  /// journals start after it (RFC 6295 C.2.2.2, RFC 4696 5.4).
  void acknowledge(int sequenceNumber) {
    final last = _next - 1;
    if (last < _first) return;
    final extended = last - ((last - sequenceNumber) & 0xFFFF);
    if (extended < _first || extended <= (_acknowledged ?? _first - 1)) {
      return;
    }
    _acknowledged = extended;
    _trim();
  }

  // ...........................................................................
  /// The session configuration.
  final MidiRtpSessionConfig config;

  /// The synchronization source of the stream.
  final int ssrc;

  /// Maps message times to RTP timestamps.
  final MidiRtpClock clock;

  /// The number of packets the open-loop journal covers.
  final int openLoopWindow;

  /// The largest journal in octets, or null without limit.
  final int? maxJournalLength;

  /// Receives messages the stream cannot carry and journal time-outs.
  final MidiIssueCallback? onIssue;

  /// The session history: the state of the stream after the packets sent
  /// so far.
  final MidiRtpStreamState history;

  /// The 16-bit sequence number of the next packet.
  int get sequenceNumber => _next & 0xFFFF;

  /// The extended sequence number of the next packet.
  int get extendedSequenceNumber => _next;

  /// The extended sequence number of the most recent acknowledged packet,
  /// or null.
  int? get acknowledged => _acknowledged;

  /// The extended sequence number of the checkpoint of the next journal.
  int get checkpoint => _checkpoint(_next);

  /// The length of the most recent journal in octets.
  int get journalLength => _journalLength;

  // ...........................................................................
  final MidiRtpJournalBuilder _builder;
  final int _first;
  int _next;
  int? _acknowledged;
  MidiTime _lastTime = const MidiTime(-0x7FFFFFFFFFFFFFFF);
  int _journalLength = 0;

  /// The least System Exclusive octets a packet carries when the journal
  /// leaves no room, so that segmentation always progresses.
  static const int _minSysExSegment = 64;

  bool _accepts(MidiMessage message) {
    final letter = switch (message) {
      MidiNoteOn() || MidiNoteOff() => 'N',
      MidiPolyPressure() => 'A',
      MidiControlChange(:final controller) =>
        (controller >= 98 && controller <= 101) ||
                history.channels[message.channel].parameterSystem.handles(
                  controller,
                )
            ? 'M'
            : 'C',
      MidiProgramChange() => 'P',
      MidiChannelPressure() => 'T',
      MidiPitchBend() => 'W',
      MidiTimeCodeQuarterFrame() => 'F',
      MidiTuneRequest() => 'G',
      MidiSongSelect() => 'H',
      MidiActiveSensing() => 'V',
      MidiSystemReset() => 'B',
      MidiSystemMessage() => 'Q',
      MidiSysEx() => 'X',
      _ => null,
    };
    if (letter == null) {
      onIssue?.call(
        MidiDiagnosticKind.untranslatable,
        'RTP MIDI carries MIDI 1.0 commands only: $message',
      );
      return false;
    }
    final allowed = switch (message) {
      MidiSysEx(:final data) => config.allowsSysEx(data),
      MidiChannelVoice1Message(:final channel) => config.allowsCommand(
        letter,
        channel: channel,
        field: switch (message) {
          MidiNoteOn(:final note) ||
          MidiNoteOff(:final note) ||
          MidiPolyPressure(:final note) => note,
          MidiControlChange(:final controller) when letter == 'C' => controller,
          _ => null,
        },
      ),
      _ => config.allowsCommand(letter),
    };
    if (!allowed) {
      onIssue?.call(
        MidiDiagnosticKind.untranslatable,
        'The session configuration excludes $message (cm_unused)',
      );
    }
    return allowed;
  }

  ({MidiRtpPacket packet, int index, int offset}) _fill(
    List<_Pending> queue,
    int start,
    int startOffset,
  ) {
    final seq = _next;
    final head = queue[start];
    final journal = _journal(seq, head.time);
    final budget = min(
      config.maxPacketSize - 14 - _journalLength,
      MidiRtpCommandSection.maxLength,
    );
    final entries = <(MidiRtpCommand, _Pending)>[];
    var used = 0;
    int? running;
    var index = start;
    var offset = startOffset;
    var timestamp = head.timestamp;
    while (index < queue.length) {
      final item = queue[index];
      final delta = (item.timestamp - timestamp) & 0xFFFFFFFF;
      final span = (item.timestamp - head.timestamp) & 0xFFFFFFFF;
      if (entries.isNotEmpty &&
          (delta > MidiRtpDeltaTime.max ||
              span > (config.maxPacketTime ?? MidiRtpDeltaTime.max))) {
        break;
      }
      final deltaTime = entries.isEmpty ? 0 : delta;
      final deltaLength = entries.isEmpty
          ? 0
          : MidiRtpDeltaTime.encodedLength(delta);
      final message = item.message;
      if (message is MidiSysEx) {
        final remaining = message.data.length - offset;
        var room = budget - used - deltaLength - 2;
        if (entries.isEmpty) room = max(room, _minSysExSegment);
        if (room >= remaining) {
          final kind = offset == 0
              ? MidiRtpSysExKind.complete
              : MidiRtpSysExKind.last;
          entries.add((
            MidiRtpSysExCommand(
              deltaTime: deltaTime,
              kind: kind,
              data: message.data.sublist(offset),
            ),
            item,
          ));
          used += deltaLength + 2 + remaining;
          offset = 0;
          index++;
          running = null;
          timestamp = item.timestamp;
          continue;
        }
        if (room > 0) {
          final kind = offset == 0
              ? MidiRtpSysExKind.first
              : MidiRtpSysExKind.middle;
          entries.add((
            MidiRtpSysExCommand(
              deltaTime: deltaTime,
              kind: kind,
              data: message.data.sublist(offset, offset + room),
            ),
            item,
          ));
          offset += room;
        }
        break;
      }
      final octets = MidiByteEncoder.encode(message)!.bytes;
      final status = octets.first;
      final cost = deltaLength + octets.length - (status == running ? 1 : 0);
      if (entries.isNotEmpty && used + cost > budget) break;
      entries.add((
        MidiRtpMessageCommand(deltaTime: deltaTime, message: message),
        item,
      ));
      used += cost;
      if (status < 0xF0) running = status;
      if (status >= 0xF0 && status < 0xF8) running = null;
      index++;
      timestamp = item.timestamp;
    }
    final packet = _packet(seq, head.timestamp, [
      for (final entry in entries) entry.$1,
    ], journal);
    for (final (command, item) in entries) {
      if (command is MidiRtpSysExCommand) {
        history.applySysEx(command.kind, command.data, seq: seq);
      } else {
        history.apply(item.message, seq: seq, time: item.time);
      }
    }
    return (packet: packet, index: index, offset: offset);
  }

  MidiRtpPacket _packet(
    int seq,
    int timestamp,
    List<MidiRtpCommand> commands,
    MidiRtpJournal? journal,
  ) {
    _next = seq + 1;
    if (config.sendingPolicy == MidiRtpSendingPolicy.openLoop) _trim();
    return MidiRtpPacket(
      header: MidiRtpHeader(
        marker: commands.isNotEmpty,
        payloadType: config.payloadType,
        sequenceNumber: seq & 0xFFFF,
        timestamp: timestamp,
        ssrc: ssrc,
      ),
      payload: MidiRtpPayload(commands: commands, journal: journal),
    );
  }

  MidiRtpJournal? _journal(int seq, MidiTime time) {
    if (!config.journal) {
      _journalLength = 0;
      return null;
    }
    var journal = _build(seq, time);
    _journalLength = journal.toBytes().length;
    final max = maxJournalLength;
    if (max != null && _journalLength > max) {
      onIssue?.call(
        MidiDiagnosticKind.networkLoss,
        'The journal of packet ${seq & 0xFFFF} grew to $_journalLength '
        'octets without receiver feedback; its history is dropped',
      );
      _acknowledged = seq - 1;
      _trim();
      journal = _build(seq, time);
      _journalLength = journal.toBytes().length;
    }
    return journal;
  }

  MidiRtpJournal _build(int seq, MidiTime time) => _builder.build(
    history,
    seq: seq,
    checkpoint: _checkpoint(seq),
    first: _first,
    time: time,
  );

  int _checkpoint(int seq) {
    final acknowledged = (_acknowledged ?? _first - 1) + 1;
    return switch (config.sendingPolicy) {
      MidiRtpSendingPolicy.anchor => _first,
      MidiRtpSendingPolicy.closedLoop => acknowledged,
      MidiRtpSendingPolicy.openLoop => max(
        max(_first, seq - openLoopWindow),
        acknowledged,
      ),
    };
  }

  void _trim() {
    if (config.sendingPolicy == MidiRtpSendingPolicy.anchor) return;
    history.trim(
      _checkpoint(_next),
      keepController: (channel, controller) =>
          config.chapterSemantics('C', channel: channel, field: controller) ==
          MidiRtpChapterSemantics.anchor,
      keepSysEx: (data) =>
          config.sysExSemantics(data) == MidiRtpChapterSemantics.anchor,
    );
  }
}

// #############################################################################
class _Pending {
  _Pending(this.message, this.time, this.timestamp);

  final MidiMessage message;
  final MidiTime time;
  final int timestamp;
}
