// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../journal/midi_rtp_channel_journal.dart';
import '../journal/midi_rtp_channel_state.dart';
import '../journal/midi_rtp_chapter_a.dart';
import '../journal/midi_rtp_chapter_c.dart';
import '../journal/midi_rtp_chapter_d.dart';
import '../journal/midi_rtp_chapter_e.dart';
import '../journal/midi_rtp_chapter_f.dart';
import '../journal/midi_rtp_chapter_m.dart';
import '../journal/midi_rtp_chapter_n.dart';
import '../journal/midi_rtp_chapter_p.dart';
import '../journal/midi_rtp_chapter_q.dart';
import '../journal/midi_rtp_chapter_t.dart';
import '../journal/midi_rtp_chapter_v.dart';
import '../journal/midi_rtp_chapter_w.dart';
import '../journal/midi_rtp_chapter_x.dart';
import '../journal/midi_rtp_controller_log.dart';
import '../journal/midi_rtp_controller_tool.dart';
import '../journal/midi_rtp_journal.dart';
import '../journal/midi_rtp_note_extra_log.dart';
import '../journal/midi_rtp_note_log.dart';
import '../journal/midi_rtp_parameter_log.dart';
import '../journal/midi_rtp_parameter_state.dart';
import '../journal/midi_rtp_pressure_log.dart';
import '../journal/midi_rtp_stream_state.dart';
import '../journal/midi_rtp_sys_ex_log.dart';
import '../journal/midi_rtp_sys_ex_status.dart';
import '../journal/midi_rtp_system_journal.dart';
import '../journal/midi_rtp_system_state.dart';
import '../journal/midi_rtp_undefined_common_log.dart';
import '../journal/midi_rtp_undefined_real_time_log.dart';
import '../session_config/midi_rtp_chapter_semantics.dart';
import '../session_config/midi_rtp_session_config.dart';

// #############################################################################
/// Builds the recovery journal of a packet from the session history of the
/// sender (RFC 6295 4, 5, Appendices A and B; RFC 4696 5).
///
/// The journal of packet I with checkpoint C codes every active command of
/// the packets C to I - 1 the chapter definitions require; chapters assigned
/// to ch_anchor cover the session history from the first packet and those
/// assigned to ch_never are left out (RFC 6295 C.2.3). S bits are 0 for
/// elements that code the previous packet. The sender codes controllers
/// with the value tool, adds the toggle tool for the pedals 64 to 67 and the
/// count tool for the channel mode controllers 120 to 127 and for the
/// controllers Reset All Controllers resets (1, 11, 64 to 67), so a
/// receiver tells their lost commands from its own; when Chapter C would
/// exceed its 128 logs, a single tool per command remains. It uses the value
/// tool for RPN and NRPN parameters, the simple SysEx typing rule with
/// COUNT in every Chapter X log, and sets the Y bit of note logs whose
/// NoteOn is at most [recentNoteOn] older than the packet. Chapter X also
/// logs finished MIDI Time Code Full Frames, optional data the definition
/// permits (RFC 6295 A.1): every command the COUNT counts is visible, so
/// receivers identify each command exactly.
final class MidiRtpJournalBuilder {
  /// Creates a builder for streams with [config]; [onIssue] learns about
  /// logs left out because a journal outgrew its 10-bit LENGTH field.
  MidiRtpJournalBuilder({
    required this.config,
    this.recentNoteOn = const Duration(milliseconds: 100),
    this.onIssue,
  }) : _enhancedChannels = [
         for (var channel = 0; channel < 16; channel++)
           config.usesEnhancedChapterC(channel),
       ];

  // ...........................................................................
  /// Returns the journal of the packet with the extended sequence number
  /// [seq] and the time [time] for the checkpoint [checkpoint]; [first] is
  /// the first packet of the stream.
  MidiRtpJournal build(
    MidiRtpStreamState history, {
    required int seq,
    required int checkpoint,
    required int first,
    MidiTime time = MidiTime.zero,
  }) {
    final context = _Context(seq, checkpoint, first, time);
    final system = _system(history.system, context);
    final channels = [
      for (final channel in history.channels) ?_channel(channel, context),
    ];
    return MidiRtpJournal(
      s: (system?.s ?? true) && channels.every((c) => c.s),
      h: _enhancedChannels.contains(true),
      checkpoint: checkpoint & 0xFFFF,
      systemJournal: system,
      channelJournals: channels,
    );
  }

  // ...........................................................................
  /// The configuration of the stream.
  final MidiRtpSessionConfig config;

  /// The age up to which a NoteOn counts as recent: its note log
  /// recommends to play it when it is recovered (Y bit, RFC 4696 4.2).
  final Duration recentNoteOn;

  /// Receives the logs left out of journals that outgrew their LENGTH.
  final MidiIssueCallback? onIssue;

  // ...........................................................................
  final List<bool> _enhancedChannels;

  /// Returns the oldest packet a chapter element covers under its
  /// semantics, or null when it never appears.
  int? _from(_Context context, MidiRtpChapterSemantics semantics) =>
      switch (semantics) {
        MidiRtpChapterSemantics.never => null,
        MidiRtpChapterSemantics.standard => context.checkpoint,
        MidiRtpChapterSemantics.anchor => context.first,
      };

  bool _covers(
    _Context context,
    int? seq,
    String letter, {
    int? channel,
    int? field,
  }) {
    if (seq == null) return false;
    final from = _from(
      context,
      config.chapterSemantics(letter, channel: channel, field: field),
    );
    return from != null && seq >= from;
  }

  // ...........................................................................
  MidiRtpChannelJournal? _channel(MidiRtpChannelState state, _Context context) {
    final c = state.channel;
    final program = state.program;
    final chapterP = _covers(context, program?.seq, 'P', channel: c)
        ? MidiRtpChapterP(
            s: context.safe(program!.seq),
            program: program.program,
            b: program.b,
            bankMsb: program.bankMsb,
            x: program.x,
            bankLsb: program.bankLsb,
          )
        : null;
    final pitch = state.pitchWheel;
    final chapterW = _covers(context, pitch?.seq, 'W', channel: c)
        ? MidiRtpChapterW(s: context.safe(pitch!.seq), value: pitch.value)
        : null;
    final pressure = state.channelPressure;
    final chapterT = _covers(context, pressure?.seq, 'T', channel: c)
        ? MidiRtpChapterT(
            s: context.safe(pressure!.seq),
            pressure: pressure.value,
          )
        : null;
    final chapters = (
      p: chapterP,
      c: _chapterC(state, context),
      m: _chapterM(state, context),
      w: chapterW,
      n: _chapterN(state, context),
      e: _chapterE(state, context),
      t: chapterT,
      a: _chapterA(state, context),
    );
    final present = [
      chapters.p?.s,
      chapters.c?.s,
      chapters.m?.s,
      chapters.w?.s,
      if (chapters.n != null)
        chapters.n!.b && chapters.n!.logs.every((log) => log.s),
      chapters.e?.s,
      chapters.t?.s,
      chapters.a?.s,
    ].nonNulls;
    if (present.isEmpty) return null;
    return _fitChannel(
      MidiRtpChannelJournal(
        s: present.every((s) => s),
        channel: c,
        h: _enhancedChannels[c],
        chapterP: chapters.p,
        chapterC: chapters.c,
        chapterM: chapters.m,
        chapterW: chapters.w,
        chapterN: chapters.n,
        chapterE: chapters.e,
        chapterT: chapters.t,
        chapterA: chapters.a,
      ),
    );
  }

  /// Leaves out the oldest logs of Chapter M, then of Chapter C, until the
  /// channel journal fits its 10-bit LENGTH field.
  ///
  /// Without these two chapters a channel journal takes 781 octets at
  /// most, so the others never need trimming.
  MidiRtpChannelJournal _fitChannel(MidiRtpChannelJournal journal) {
    var m = journal.chapterM;
    var c = journal.chapterC;
    int length() =>
        3 +
        (journal.chapterP == null ? 0 : MidiRtpChapterP.length) +
        (c?.length ?? 0) +
        (m?.toBytes().length ?? 0) +
        (journal.chapterW == null ? 0 : MidiRtpChapterW.length) +
        (journal.chapterN?.length ?? 0) +
        (journal.chapterE?.length ?? 0) +
        (journal.chapterT == null ? 0 : MidiRtpChapterT.length) +
        (journal.chapterA?.length ?? 0);
    var dropped = 0;
    while (length() > 0x3FF) {
      dropped++;
      if (m != null && m.logs.isNotEmpty) {
        m = m.copyWith(logs: m.logs.skip(1));
      } else {
        c = c!.copyWith(logs: c.logs.skip(1));
      }
    }
    if (dropped == 0) return journal;
    onIssue?.call(
      MidiDiagnosticKind.queueOverflow,
      'The journal of channel ${journal.channel} exceeds 1023 octets; '
      '$dropped oldest logs are left out',
    );
    return journal.copyWith(chapterM: m, chapterC: c);
  }

  // ...........................................................................
  MidiRtpChapterC? _chapterC(MidiRtpChannelState state, _Context context) {
    var logs = _controllerLogs(state, context, full: true);
    if (logs.length > 128) logs = _controllerLogs(state, context, full: false);
    if (logs.isEmpty) return null;
    if (logs.length > 128) {
      onIssue?.call(
        MidiDiagnosticKind.queueOverflow,
        'Chapter C of channel ${state.channel} holds 128 logs; '
        '${logs.length - 128} oldest logs are left out',
      );
      logs = logs.sublist(logs.length - 128);
    }
    return MidiRtpChapterC(s: logs.every((log) => log.s), logs: logs);
  }

  /// Returns the controller logs oldest first; without [full] tools a
  /// command gets one log, two for 122 and 126, to fit the 128 logs of
  /// Chapter C.
  List<MidiRtpControllerLog> _controllerLogs(
    MidiRtpChannelState state,
    _Context context, {
    required bool full,
  }) {
    final c = state.channel;
    final commands = <(int, List<MidiRtpControllerLog>)>[];
    for (final number in state.controllers) {
      final from = _from(
        context,
        config.chapterSemantics('C', channel: c, field: number),
      );
      if (from == null) continue;
      if (config.isEnhanced(c, number)) {
        for (final command in state.controllerHistory(number)) {
          if (command.seq < from) continue;
          commands.add((
            command.order,
            _logs(number, command, context, count: true),
          ));
        }
      } else {
        final command = state.controller(number)!;
        if (command.seq >= from) {
          commands.add((
            command.order,
            full
                ? _logs(number, command, context)
                : _minimalLogs(number, command, context),
          ));
        }
      }
    }
    commands.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final command in commands) ...command.$2];
  }

  /// The controllers whose count tool tells a lost command apart from the
  /// receiver's own: the channel mode controllers, and those Reset All
  /// Controllers resets (RP-015), whose values may repeat.
  static bool _counted(int number) =>
      number >= 120 ||
      number == 1 ||
      number == 11 ||
      (number >= 64 && number <= 67);

  List<MidiRtpControllerLog> _logs(
    int number,
    MidiRtpControllerValue command,
    _Context context, {
    bool count = false,
  }) {
    final s = context.safe(command.seq);
    MidiRtpControllerLog log(MidiRtpControllerTool tool, int value) =>
        MidiRtpControllerLog(s: s, number: number, tool: tool, value: value);
    return [
      if (count || _counted(number))
        log(MidiRtpControllerTool.count, command.count),
      log(MidiRtpControllerTool.value, command.value),
      if (number >= 64 && number <= 67)
        log(MidiRtpControllerTool.toggle, command.toggles),
    ];
  }

  List<MidiRtpControllerLog> _minimalLogs(
    int number,
    MidiRtpControllerValue command,
    _Context context,
  ) {
    final s = context.safe(command.seq);
    final action = number >= 120 && number != 122 && number != 126;
    return [
      if (number >= 120)
        MidiRtpControllerLog(
          s: s,
          number: number,
          tool: MidiRtpControllerTool.count,
          value: command.count,
        ),
      if (!action)
        MidiRtpControllerLog(
          s: s,
          number: number,
          tool: MidiRtpControllerTool.value,
          value: command.value,
        ),
    ];
  }

  // ...........................................................................
  MidiRtpChapterM? _chapterM(MidiRtpChannelState state, _Context context) {
    final c = state.channel;
    final system = state.parameterSystem;
    final selection = system.selection;
    final current = system.inProgress && selection != null
        ? (nrpn: selection.nrpn, number: selection.number)
        : null;
    final logs = <MidiRtpParameterLog>[];
    for (final p in system.parameters) {
      final field = p.nrpn ? 0x4000 + p.number : p.number;
      final semantics = config.chapterSemantics('M', channel: c, field: field);
      final from = _from(context, semantics);
      final isCurrent = current?.nrpn == p.nrpn && current?.number == p.number;
      if (from != null && (p.seq >= from || isCurrent)) {
        logs.add(_parameterLog(p, context));
      } else if (from == null && isCurrent && p.seq >= context.checkpoint) {
        logs.add(
          MidiRtpParameterLog(
            s: context.safe(p.seq),
            nrpn: p.nrpn,
            number: p.number,
            v: false,
          ),
        );
      }
    }
    final selectionSeq = system.selectionSeq;
    final required =
        selectionSeq != null &&
        selectionSeq >= context.checkpoint &&
        config.chapterSemantics('M', channel: c) !=
            MidiRtpChapterSemantics.never;
    if (logs.isEmpty && !required) return null;
    final u = logs.isNotEmpty && logs.every((log) => !log.nrpn);
    final w = logs.isNotEmpty && logs.every((log) => log.nrpn);
    final z = logs.isNotEmpty && logs.every((log) => log.number <= 0x7F);
    return MidiRtpChapterM(
      s:
          logs.every((log) => log.s) &&
          (selectionSeq == null || context.safe(selectionSeq)),
      pending: system.pending,
      e: system.inProgress,
      u: u,
      w: w,
      z: z,
      logs: logs,
    );
  }

  MidiRtpParameterLog _parameterLog(MidiRtpParameterValue p, _Context context) {
    final aButton = p.aButton;
    return MidiRtpParameterLog(
      s: context.safe(p.seq),
      nrpn: p.nrpn,
      number: p.number,
      entryMsb: p.entryMsb == null
          ? null
          : (value: p.entryMsb!.value, x: p.entryMsb!.x),
      entryLsb: p.entryLsb == null
          ? null
          : (value: p.entryLsb!.value, x: p.entryLsb!.x),
      aButton: aButton == null ? null : (count: aButton.count, x: aButton.x),
      cButton: aButton == null || p.cButton == aButton.count ? null : p.cButton,
    );
  }

  // ...........................................................................
  MidiRtpChapterN? _chapterN(MidiRtpChannelState state, _Context context) {
    final c = state.channel;
    final logs = <MidiRtpNoteLog>[];
    final offNotes = <int>[];
    for (final number in state.notes) {
      final note = state.note(number)!;
      if (!_covers(context, note.seq, 'N', channel: c, field: number)) {
        continue;
      }
      if (note.on) {
        logs.add(
          MidiRtpNoteLog(
            s: context.safe(note.seq),
            note: number,
            y: context.time.difference(note.time) <= recentNoteOn,
            velocity: note.velocity,
          ),
        );
      } else {
        offNotes.add(number);
      }
    }
    if (logs.isEmpty && offNotes.isEmpty) return null;
    return MidiRtpChapterN(
      b: context.safe(state.noteOffSeq),
      logs: logs,
      offNotes: offNotes,
    );
  }

  // ...........................................................................
  MidiRtpChapterE? _chapterE(MidiRtpChannelState state, _Context context) {
    final c = state.channel;
    final logs = <MidiRtpNoteExtraLog>[];
    for (final number in state.notes) {
      final note = state.note(number)!;
      if (!_covers(context, note.seq, 'N', channel: c, field: number)) {
        continue;
      }
      final s = context.safe(note.seq);
      if ((note.on ? note.count > 1 : note.count > 0) &&
          _covers(context, note.seq, 'E', channel: c, field: 0)) {
        logs.add(
          MidiRtpNoteExtraLog(
            s: s,
            note: number,
            v: false,
            value: note.count > 127 ? 127 : note.count,
          ),
        );
      }
      if (!note.on &&
          note.releaseVelocity != 64 &&
          _covers(context, note.seq, 'E', channel: c, field: 1)) {
        logs.add(
          MidiRtpNoteExtraLog(
            s: s,
            note: number,
            v: true,
            value: note.releaseVelocity,
          ),
        );
      }
    }
    // Chapter E holds 128 logs at most; release velocity logs go first.
    var excess = logs.length - 128;
    logs.removeWhere((log) => log.v && excess-- > 0);
    if (logs.isEmpty) return null;
    return MidiRtpChapterE(s: logs.every((log) => log.s), logs: logs);
  }

  // ...........................................................................
  MidiRtpChapterA? _chapterA(MidiRtpChannelState state, _Context context) {
    final c = state.channel;
    final logs = [
      for (final number in state.polyPressureNotes)
        if (_covers(
          context,
          state.polyPressure(number)!.seq,
          'A',
          channel: c,
          field: number,
        ))
          MidiRtpPressureLog(
            s: context.safe(state.polyPressure(number)!.seq),
            note: number,
            x: state.polyPressure(number)!.x,
            pressure: state.polyPressure(number)!.value,
          ),
    ];
    if (logs.isEmpty) return null;
    return MidiRtpChapterA(s: logs.every((log) => log.s), logs: logs);
  }

  // ...........................................................................
  MidiRtpSystemJournal? _system(MidiRtpSystemState state, _Context context) {
    final chapterD = _chapterD(state, context);
    final chapterV = _covers(context, state.activeSenseSeq, 'V')
        ? MidiRtpChapterV(
            s: context.safe(state.activeSenseSeq),
            count: state.activeSenseCount,
          )
        : null;
    final chapterQ = _chapterQ(state, context);
    final chapterF = _chapterF(state, context);
    final chapterX = _fitX(
      _chapterX(state, context),
      2 +
          (chapterD?.toBytes().length ?? 0) +
          (chapterV == null ? 0 : MidiRtpChapterV.length) +
          (chapterQ?.toBytes().length ?? 0) +
          (chapterF?.toBytes().length ?? 0),
    );
    final present = [
      chapterD?.s,
      chapterV?.s,
      chapterQ?.s,
      chapterF?.s,
      chapterX?.s,
    ].nonNulls;
    if (present.isEmpty) return null;
    return MidiRtpSystemJournal(
      s: present.every((s) => s),
      chapterD: chapterD,
      chapterV: chapterV,
      chapterQ: chapterQ,
      chapterF: chapterF,
      chapterX: chapterX,
    );
  }

  MidiRtpChapterD? _chapterD(MidiRtpSystemState state, _Context context) {
    ({bool s, int value})? simple(int? seq, String letter, int value) =>
        _covers(context, seq, letter)
        ? (s: context.safe(seq), value: value)
        : null;
    final song = state.songSelect;
    MidiRtpUndefinedCommonLog? common(int status, String letter) {
      final command = state.undefined(status);
      if (!_covers(context, command?.seq, letter)) return null;
      return MidiRtpUndefinedCommonLog(
        s: context.safe(command!.seq),
        dsz: MidiRtpUndefinedCommonLog.dszOf(command.data.length),
        count: state.undefinedCount(status),
        value: command.data.isEmpty ? null : command.data,
      );
    }

    MidiRtpUndefinedRealTimeLog? realTime(int status, String letter) {
      final command = state.undefined(status);
      if (!_covers(context, command?.seq, letter)) return null;
      return MidiRtpUndefinedRealTimeLog(
        s: context.safe(command!.seq),
        count: state.undefinedCount(status),
      );
    }

    final chapter = MidiRtpChapterD(
      reset: simple(state.resetSeq, 'B', state.resetCount),
      tuneRequest: simple(state.tuneRequestSeq, 'G', state.tuneRequestCount),
      songSelect: simple(song?.seq, 'H', song?.value ?? 0),
      f4: common(0xF4, 'J'),
      f5: common(0xF5, 'K'),
      f9: realTime(0xF9, 'Y'),
      fd: realTime(0xFD, 'Z'),
    );
    final present = [
      chapter.reset?.s,
      chapter.tuneRequest?.s,
      chapter.songSelect?.s,
      chapter.f4?.s,
      chapter.f5?.s,
      chapter.f9?.s,
      chapter.fd?.s,
    ].nonNulls;
    if (present.isEmpty) return null;
    return chapter.copyWith(s: present.every((s) => s));
  }

  MidiRtpChapterQ? _chapterQ(MidiRtpSystemState state, _Context context) {
    if (!_covers(context, state.sequencerSeq, 'Q', channel: 0)) return null;
    final q = state.sequencer;
    final c = q.position != 0 || (q.running && !q.downbeat && !q.startRecent);
    return MidiRtpChapterQ(
      s: context.safe(state.sequencerSeq),
      n: q.running,
      d: q.downbeat,
      position: c ? q.position : null,
    );
  }

  MidiRtpChapterF? _chapterF(MidiRtpSystemState state, _Context context) {
    if (!_covers(context, state.timeCodeSeq, 'F')) return null;
    final complete = state.completeFrame;
    final partial = state.partialFrame;
    return MidiRtpChapterF(
      s: context.safe(state.timeCodeSeq),
      complete: complete?.field,
      q: complete?.q ?? false,
      d: state.reverse,
      point: partial?.point ?? (state.reverse ? 0 : 7),
      partial: partial?.field,
    );
  }

  /// Leaves out the oldest logs of [chapter] until the system journal with
  /// [others] octets of other content fits its 10-bit LENGTH field.
  MidiRtpChapterX? _fitX(MidiRtpChapterX? chapter, int others) {
    if (chapter == null) return null;
    final logs = chapter.logs.toList();
    final s = chapter.s;
    var length = others + chapter.toBytes().length;
    var dropped = 0;
    while (length > 0x3FF && logs.isNotEmpty) {
      length -= logs.removeAt(0).toBytes().length;
      dropped++;
    }
    if (dropped == 0) return chapter;
    onIssue?.call(
      MidiDiagnosticKind.sysExTooLong,
      'The system journal exceeds 1023 octets; $dropped oldest System '
      'Exclusive logs are left out',
    );
    if (logs.isEmpty) return null;
    return MidiRtpChapterX(
      logs: [
        logs.first.copyWith(s: s),
        ...logs.skip(1),
      ],
    );
  }

  MidiRtpChapterX? _chapterX(MidiRtpSystemState state, _Context context) {
    final logs = <MidiRtpSysExLog>[];
    for (final record in state.sysEx) {
      final from = _from(context, config.sysExSemantics(record.data));
      if (from == null || record.seq < from) continue;
      // The last chunk belongs to the packet of the record, so a covered
      // record has a covered chunk.
      final first = record.chunks
          .firstWhere((chunk) => chunk.seq >= from)
          .offset;
      final data = record.status == MidiRtpSysExStatus.cancelled
          ? const <int>[]
          : record.data.sublist(first);
      logs.add(
        MidiRtpSysExLog(
          s: context.safe(record.seq),
          count: record.count,
          first: first == 0 ? null : first,
          data: data.isEmpty ? null : data,
          status: record.status,
        ),
      );
    }
    if (logs.isEmpty) return null;
    final s = logs.every((log) => log.s);
    return MidiRtpChapterX(
      logs: [
        logs.first.copyWith(s: s),
        ...logs.skip(1),
      ],
    );
  }
}

// #############################################################################
class _Context {
  _Context(this.seq, this.checkpoint, this.first, this.time);

  final int seq;
  final int checkpoint;
  final int first;
  final MidiTime time;

  /// Returns the S bit of an element of the packet [elementSeq]: false
  /// when it codes the previous packet.
  bool safe(int? elementSeq) => elementSeq != seq - 1;
}
