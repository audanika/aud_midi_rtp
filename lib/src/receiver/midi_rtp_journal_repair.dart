// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:math';

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
import '../journal/midi_rtp_chapter_x.dart';
import '../journal/midi_rtp_controller_tool.dart';
import '../journal/midi_rtp_journal.dart';
import '../journal/midi_rtp_note_extra_log.dart';
import '../journal/midi_rtp_note_log.dart';
import '../journal/midi_rtp_stream_state.dart';
import '../journal/midi_rtp_sys_ex_status.dart';
import '../journal/midi_rtp_system_journal.dart';
import '../journal/midi_rtp_time_code.dart';
import '../journal/midi_rtp_undefined_common_log.dart';
import '../journal/midi_rtp_undefined_real_time_log.dart';
import '../payload/midi_rtp_sys_ex_kind.dart';

// #############################################################################
/// Repairs the MIDI state of a receiver from the recovery journal of the
/// packet that ends a loss event (RFC 6295 4, Appendices A and B; RFC 4696
/// 7).
///
/// The repair compares each chapter with the receiver's [model] of the
/// stream and returns the MIDI commands that turn every indefinite artifact
/// into a transient one: lost NoteOffs, controllers, programs, pitch wheel,
/// parameters, pressure, sequencer, time code and System Exclusive. Each
/// repair command is applied to the model at once, so later chapters
/// compare with the repaired state. A lost System Reset goes first, then
/// Chapter X (whose oldest log is a lost Reset State System Exclusive, if
/// any), the other system chapters with Chapter F last, then the channel
/// journals in the chapter order P, C, M, W, N, E, T, A: Chapter C replays
/// Reset All Controllers and All Notes Off before the chapters whose
/// commands follow them. Chapter X identifies commands by their COUNT.
/// After the loss of a single packet, elements with the S bit set are
/// skipped.
final class MidiRtpJournalRepair {
  /// Creates a repair of [model]; [onIssue] receives what cannot be
  /// repaired.
  MidiRtpJournalRepair({required this.model, this.onIssue});

  // ...........................................................................
  /// Returns the repair commands for [journal], the journal of the packet
  /// with the extended sequence number [seq] and the extended
  /// [checkpoint].
  ///
  /// - [singleLoss] only the previous packet is lost: S bits apply.
  /// - [covered] the checkpoint history covers the whole loss; otherwise
  ///   notes the journal does not confirm are ended, erring on the side of
  ///   caution (RFC 6295 C.2.2.2, C.2.2.3).
  List<MidiMessage> repair(
    MidiRtpJournal journal, {
    required int seq,
    required int checkpoint,
    bool singleLoss = false,
    bool covered = true,
  }) {
    _out = [];
    _seq = seq;
    _checkpoint = checkpoint;
    _single = singleLoss;
    if (!(_single && journal.s)) {
      final system = journal.systemJournal;
      if (system != null && !(_single && system.s)) _system(system);
      for (final channel in journal.channelJournals) {
        if (!(_single && channel.s)) _channel(channel);
      }
    }
    if (!covered) _silenceUnconfirmed(journal);
    return _out;
  }

  /// Returns the commands that end every note the model holds, and release
  /// the sustaining pedals 64, 66 and 69, e.g. when a stream ends (RFC 6295
  /// 4: a receiver leaves no indefinite artifact when it exits).
  List<MidiMessage> silence({required int seq}) {
    _out = [];
    _seq = seq;
    for (final state in model.channels) {
      for (final note in state.notes) {
        _endNote(state, note, 64, keep: 0);
      }
      for (final pedal in const [64, 66, 69]) {
        if ((state.controllerValue(pedal) ?? 0) >= 64) {
          _control(state.channel, pedal, 0);
        }
      }
    }
    return _out;
  }

  // ...........................................................................
  /// The receiver's model of the stream.
  final MidiRtpStreamState model;

  /// Receives what cannot be repaired.
  final MidiIssueCallback? onIssue;

  // ...........................................................................
  List<MidiMessage> _out = [];
  int _seq = 0;
  int _checkpoint = 0;
  bool _single = false;

  void _emit(MidiMessage message) {
    model.apply(message, seq: _seq);
    _out.add(message);
  }

  void _control(int channel, int controller, int value) => _emit(
    MidiControlChange(channel: channel, controller: controller, value: value),
  );

  bool _skip(bool s) => _single && s;

  // ...........................................................................
  void _system(MidiRtpSystemJournal journal) {
    final d = journal.chapterD;
    final x = journal.chapterX;
    if (d != null && !_skip(d.s)) _reset(d.reset);
    if (x != null) _chapterX(x);
    if (d != null && !_skip(d.s)) _chapterD(d);
    final v = journal.chapterV;
    if (v != null && !_skip(v.s) && v.count != model.system.activeSenseCount) {
      _emit(const MidiActiveSensing());
      model.system.syncCounts(activeSenseCount: v.count);
    }
    final q = journal.chapterQ;
    if (q != null && !_skip(q.s)) _chapterQ(q);
    final f = journal.chapterF;
    if (f != null && !_skip(f.s)) _chapterF(f);
  }

  void _reset(({bool s, int value})? log) {
    if (log == null || _skip(log.s)) return;
    if (model.system.resetCount != log.value) _emit(const MidiSystemReset());
    model.system.syncCounts(resetCount: log.value);
  }

  void _chapterD(MidiRtpChapterD chapter) {
    final system = model.system;
    final tune = chapter.tuneRequest;
    if (tune != null && !_skip(tune.s)) {
      if (tune.value != system.tuneRequestCount) {
        _emit(const MidiTuneRequest());
      }
      system.syncCounts(tuneRequestCount: tune.value);
    }
    final song = chapter.songSelect;
    if (song != null &&
        !_skip(song.s) &&
        system.songSelect?.value != song.value) {
      _emit(MidiSongSelect(song: song.value));
    }
    _undefinedCommon(0xF4, chapter.f4);
    _undefinedCommon(0xF5, chapter.f5);
    _undefinedRealTime(0xF9, chapter.f9);
    _undefinedRealTime(0xFD, chapter.fd);
  }

  void _undefinedCommon(int status, MidiRtpUndefinedCommonLog? log) {
    if (log == null || _skip(log.s)) return;
    final system = model.system;
    final count = log.count;
    final lost = count != null
        ? count != system.undefinedCount(status)
        : log.value != null &&
              !_sameList(log.value, system.undefined(status)?.data);
    if (!lost) return;
    final data = log.value ?? const <int>[];
    if (data.length > 2) {
      onIssue?.call(
        MidiDiagnosticKind.untranslatable,
        'Undefined command 0x${status.toRadixString(16)} with '
        '${data.length} data octets has no message form',
      );
    } else {
      _out.add(undefinedMessage(status, data));
    }
    system.applyUndefined(status, data, seq: _seq);
    if (count != null) system.syncUndefinedCount(status, count);
  }

  void _undefinedRealTime(int status, MidiRtpUndefinedRealTimeLog? log) {
    if (log == null || _skip(log.s) || log.count == null) return;
    final system = model.system;
    if (log.count == system.undefinedCount(status)) return;
    _out.add(undefinedMessage(status, const []));
    system.applyUndefined(status, const [], seq: _seq);
    system.syncUndefinedCount(status, log.count!);
  }

  // ...........................................................................
  void _chapterQ(MidiRtpChapterQ chapter) {
    final current = model.system.sequencer;
    final position = chapter.position ?? 0;
    if (current.running == chapter.n &&
        current.downbeat == chapter.d &&
        current.position == position) {
      return;
    }
    if (current.running) _emit(const MidiStop());
    final beats = min(position ~/ 6, 0x3FFF);
    if (!chapter.d && position == 0 && chapter.n && chapter.position == null) {
      _emit(const MidiStart());
      return;
    }
    _emit(MidiSongPositionPointer(position: beats));
    if (chapter.d) {
      _emit(const MidiContinue());
      final clocks = min(position - beats * 6 + 1, 6);
      for (var i = 0; i < clocks; i++) {
        _emit(const MidiTimingClock());
      }
      if (!chapter.n) _emit(const MidiStop());
    } else if (chapter.n) {
      _emit(const MidiContinue());
    }
  }

  void _chapterF(MidiRtpChapterF chapter) {
    final system = model.system;
    final complete = chapter.complete;
    final target = complete == null
        ? null
        : MidiRtpTimeCode.fromField(complete, nibbles: chapter.q);
    final current = system.completeFrame;
    final currentCode = current == null
        ? null
        : MidiRtpTimeCode.fromField(current.field, nibbles: current.q);
    final partial = chapter.partial;
    final currentPartial = system.partialFrame;
    final partialDiffers = partial == null
        ? currentPartial != null
        : currentPartial == null ||
              currentPartial.field != partial ||
              currentPartial.point != chapter.point ||
              system.reverse != chapter.d;
    final relocate =
        target != null && (target != currentCode || partialDiffers);
    if (target != null && relocate) {
      final data = [0x7F, 0x7F, 0x01, 0x01, ...target.toFullFrame()];
      // The relocation touches the time code only: it is no System
      // Exclusive command of the stream, so it neither counts for the
      // Chapter X COUNT nor ends a segmented command in progress.
      model.system.locate(target, seq: _seq);
      _out.add(MidiSysEx(data));
    }
    if (partial != null && (relocate || partialDiffers)) {
      final pieces = chapter.d
          ? [for (var t = 7; t >= chapter.point; t--) t]
          : [for (var t = 0; t <= chapter.point; t++) t];
      for (final piece in pieces) {
        _emit(
          MidiTimeCodeQuarterFrame(
            piece: piece,
            value: (partial >> (4 * (7 - piece))) & 0x0F,
          ),
        );
      }
    }
  }

  void _chapterX(MidiRtpChapterX chapter) {
    final system = model.system;
    for (var i = 0; i < chapter.logs.length; i++) {
      final log = chapter.logs[i];
      if (_single && chapter.isSafe(i)) continue;
      final count = log.count;
      final unfinished = system.unfinishedSysEx;
      final first = log.first ?? 0;
      final data = log.data ?? const <int>[];
      final distance = count == null
          ? null
          : (count - system.sysExCount) & 0xFF;
      final isNew = distance == null
          ? log.status.isComplete &&
                first == 0 &&
                !_sameList(data, system.sysEx.lastOrNull?.data)
          : distance != 0 && distance < 0x80;
      if (isNew) {
        if (count != null) system.syncCounts(sysExCount: count - 1);
        if (first != 0) {
          onIssue?.call(
            MidiDiagnosticKind.sysExIncomplete,
            'The start of a lost System Exclusive command is not covered',
          );
        } else if (log.status.isComplete) {
          model.applySysEx(
            MidiRtpSysExKind.complete,
            data,
            droppedF7: log.status == MidiRtpSysExStatus.droppedF7,
            seq: _seq,
          );
          _out.add(MidiSysEx(data));
        } else if (log.status == MidiRtpSysExStatus.unfinished) {
          model.applySysEx(MidiRtpSysExKind.first, data, seq: _seq);
        }
        if (count != null) system.syncCounts(sysExCount: count);
      } else if (unfinished != null && count == unfinished.count) {
        _continueSysEx(unfinished.data.length, first, data, log.status);
      }
    }
  }

  void _continueSysEx(
    int have,
    int first,
    List<int> data,
    MidiRtpSysExStatus status,
  ) {
    if (first <= have && first + data.length > have) {
      model.applySysEx(
        MidiRtpSysExKind.middle,
        data.sublist(have - first),
        seq: _seq,
      );
    }
    if (status == MidiRtpSysExStatus.cancelled) {
      model.applySysEx(MidiRtpSysExKind.cancel, const [], seq: _seq);
    } else if (status.isComplete) {
      final completed = model.applySysEx(
        MidiRtpSysExKind.last,
        const [],
        droppedF7: status == MidiRtpSysExStatus.droppedF7,
        seq: _seq,
      );
      _out.add(MidiSysEx(completed!));
    }
  }

  // ...........................................................................
  void _channel(MidiRtpChannelJournal journal) {
    final state = model.channels[journal.channel];
    final p = journal.chapterP;
    if (p != null && !_skip(p.s)) _chapterP(state, p);
    final c = journal.chapterC;
    if (c != null && !_skip(c.s)) _chapterC(state, c);
    final m = journal.chapterM;
    if (m != null && !_skip(m.s)) _chapterM(state, m);
    final w = journal.chapterW;
    if (w != null && !_skip(w.s) && state.pitchWheel?.value != w.value) {
      _emit(MidiPitchBend(channel: state.channel, value: w.value));
    }
    final n = journal.chapterN;
    if (n != null) _chapterN(state, n, journal.chapterE);
    final t = journal.chapterT;
    if (t != null &&
        !_skip(t.s) &&
        state.channelPressure?.value != t.pressure) {
      _emit(MidiChannelPressure(channel: state.channel, pressure: t.pressure));
    }
    final a = journal.chapterA;
    if (a != null && !_skip(a.s)) _chapterA(state, a);
  }

  void _chapterP(MidiRtpChannelState state, MidiRtpChapterP chapter) {
    final program = state.program;
    if (program != null &&
        program.program == chapter.program &&
        (!chapter.b ||
            (program.b &&
                program.bankMsb == chapter.bankMsb &&
                program.bankLsb == chapter.bankLsb))) {
      return;
    }
    if (chapter.b) {
      final bank = state.bank;
      if (bank.msb != chapter.bankMsb) {
        _control(state.channel, 0, chapter.bankMsb);
      }
      final lsb = bank.msb == chapter.bankMsb ? bank.lsb ?? 0 : 0;
      if (lsb != chapter.bankLsb) {
        _control(state.channel, 32, chapter.bankLsb);
      }
    }
    _emit(MidiProgramChange(channel: state.channel, program: chapter.program));
  }

  // ...........................................................................
  void _chapterC(MidiRtpChannelState state, MidiRtpChapterC chapter) {
    final logs = [
      for (final log in chapter.logs)
        if (!_skip(log.s)) log,
    ];
    final hasReset = chapter.logs.any((log) => log.number == 121);
    var resetSeen = false;
    var i = 0;
    while (i < logs.length) {
      final number = logs[i].number;
      final tools = <MidiRtpControllerTool, int>{};
      for (final tool in MidiRtpControllerTool.values) {
        if (i < logs.length &&
            logs[i].number == number &&
            logs[i].tool == tool) {
          tools[tool] = logs[i++].value;
        }
      }
      _controller(
        state,
        number,
        count: tools[MidiRtpControllerTool.count],
        value: tools[MidiRtpControllerTool.value],
        toggles: tools[MidiRtpControllerTool.toggle],
        afterReset: !hasReset || resetSeen,
      );
      if (number == 121) resetSeen = true;
    }
  }

  void _controller(
    MidiRtpChannelState state,
    int number, {
    required int? count,
    required int? value,
    required int? toggles,
    required bool afterReset,
  }) {
    final command = state.controller(number);
    if (count != null) {
      // The count tells the command apart: 0 is the model's own, a count
      // behind is an older command of the enhanced encoding.
      final lost = (count - state.controllerCount(number)) & 0x3F;
      if (lost >= 0x20) return;
      if (lost != 0) {
        _apply(state, number, value ?? _defaultValue(number), toggles);
      }
      state.setControllerTools(number, count: count, toggles: toggles);
      return;
    }
    // Without the count tool, a command after a Reset All Controllers the
    // model holds before its own command of this number is a newer one.
    final reset = state.controller(121);
    final newer =
        afterReset &&
        command != null &&
        reset != null &&
        command.order < reset.order;
    final changed = value != null
        ? newer || command?.value != value
        : toggles != (command?.toggles ?? state.controllerToggles(number));
    if (!changed) return;
    _apply(state, number, value ?? _defaultValue(number), toggles);
    if (toggles != null) state.setControllerTools(number, toggles: toggles);
  }

  /// Emits [value] for [number]; when the lost commands toggled the
  /// controller an even number of times and it is on, an off command first
  /// damps what the lost off command would have damped (RFC 4696 7.3).
  void _apply(MidiRtpChannelState state, int number, int value, int? toggles) {
    // Chapter C codes 6, 38, 96 and 97 only as general-purpose
    // controllers: a selection the model still holds is closed first, and
    // Chapter M restores the selection of the stream afterwards.
    if (state.parameterSystem.handles(number)) {
      _control(state.channel, 101, 127);
      _control(state.channel, 100, 127);
    }
    final on = (state.controllerValue(number) ?? 0) >= 64;
    if (toggles != null) {
      final lost = (toggles - state.controllerToggles(number)) & 0x3F;
      if (lost != 0 && lost.isEven && on) _control(state.channel, number, 0);
    }
    _control(state.channel, number, value);
  }

  static int _defaultValue(int controller) => switch (controller) {
    7 => 100,
    8 || 10 || (>= 70 && <= 79) => 64,
    11 || 122 => 127,
    _ => 0,
  };

  // ...........................................................................
  void _chapterM(MidiRtpChannelState state, MidiRtpChapterM chapter) {
    final system = state.parameterSystem;
    final channel = state.channel;
    void select(bool nrpn, int number) {
      _control(channel, nrpn ? 99 : 101, number >> 7);
      _control(channel, nrpn ? 98 : 100, number & 0x7F);
    }

    for (final log in chapter.logs) {
      if (_skip(log.s) || !log.v) continue;
      final p = system.parameter(nrpn: log.nrpn, number: log.number);
      final entered = log.entryMsb != null || log.entryLsb != null;
      final msb = log.entryMsb?.value ?? p?.entryMsb?.value;
      final lsb = log.entryLsb != null
          ? log.entryLsb!.value
          : log.entryMsb != null
          ? null
          : p?.entryLsb?.value;
      final buttons =
          log.aButton?.count ?? (entered ? 0 : p?.aButton?.count ?? 0);
      final currentButtons = p?.aButton?.count ?? 0;
      final sameEntry = msb == p?.entryMsb?.value && lsb == p?.entryLsb?.value;
      if (sameEntry && buttons == currentButtons) continue;
      select(log.nrpn, log.number);
      var steps = buttons - currentButtons;
      if (!sameEntry && (msb != null || lsb != null)) {
        if (msb != null) _control(channel, 6, msb);
        if (lsb != null) _control(channel, 38, lsb);
        steps = buttons;
      }
      for (var i = 0; i < steps.abs(); i++) {
        _control(channel, steps > 0 ? 96 : 97, 0);
      }
    }
    final selection = system.selection;
    final pending = chapter.pending;
    if (pending != null) {
      if (selection == null ||
          !selection.pending ||
          selection.nrpn != pending.nrpn ||
          selection.number >> 7 != pending.value) {
        _control(channel, pending.nrpn ? 99 : 101, pending.value);
      }
    } else if (chapter.e) {
      final last = chapter.logs.lastOrNull;
      if (last != null &&
          (selection == null ||
              selection.pending ||
              selection.nrpn != last.nrpn ||
              selection.number != last.number)) {
        select(last.nrpn, last.number);
      }
    } else if (selection != null) {
      _control(channel, 101, 127);
      _control(channel, 100, 127);
    }
  }

  // ...........................................................................
  void _chapterN(
    MidiRtpChannelState state,
    MidiRtpChapterN chapter,
    MidiRtpChapterE? extras,
  ) {
    final counts = <int, int>{};
    final velocities = <int, int>{};
    for (final log in extras?.logs ?? const <MidiRtpNoteExtraLog>[]) {
      (log.v ? velocities : counts)[log.note] = log.value;
    }
    if (!_skip(chapter.b)) {
      for (final note in chapter.offNotes) {
        final keep = counts[note] ?? 0;
        _endNote(state, note, velocities[note] ?? 64, keep: keep);
        state.setNoteCount(note, keep);
      }
    }
    for (final log in chapter.logs) {
      if (_skip(log.s)) continue;
      final note = state.note(log.note);
      final count = counts[log.note] ?? 1;
      final same =
          note != null &&
          note.on &&
          note.velocity == log.velocity &&
          note.seq >= _checkpoint;
      if (!same) {
        if (note != null && note.on) _endNote(state, log.note, 64, keep: 0);
        final noteOn = MidiNoteOn(
          channel: state.channel,
          note: log.note,
          velocity: log.velocity,
        );
        if (log.y) {
          _emit(noteOn);
        } else {
          model.apply(noteOn, seq: _seq);
        }
      }
      state.setNoteCount(log.note, count);
    }
  }

  /// Ends the voices of [note] beyond [keep]: at least one NoteOff when it
  /// sounds.
  void _endNote(
    MidiRtpChannelState state,
    int note,
    int velocity, {
    required int keep,
  }) {
    final value = state.note(note);
    if (value == null) return;
    final voices = max(value.count - keep, value.on ? 1 : 0);
    for (var i = 0; i < voices; i++) {
      _emit(
        MidiNoteOff(channel: state.channel, note: note, velocity: velocity),
      );
    }
  }

  void _chapterA(MidiRtpChannelState state, MidiRtpChapterA chapter) {
    for (final log in chapter.logs) {
      if (_skip(log.s) || state.polyPressure(log.note)?.value == log.pressure) {
        continue;
      }
      _emit(
        MidiPolyPressure(
          channel: state.channel,
          note: log.note,
          pressure: log.pressure,
        ),
      );
    }
  }

  // ...........................................................................
  void _silenceUnconfirmed(MidiRtpJournal journal) {
    for (final state in model.channels) {
      final confirmed = {
        for (final log
            in journal.channelJournal(state.channel)?.chapterN?.logs ??
                const <MidiRtpNoteLog>[])
          log.note,
      };
      for (final note in state.notes) {
        if (!confirmed.contains(note)) _endNote(state, note, 64, keep: 0);
      }
    }
  }

  // ...........................................................................
  /// Returns the message form of an undefined system command: a UMP
  /// system message with the status and up to two data octets.
  static MidiUnknownMessage undefinedMessage(int status, List<int> data) =>
      MidiUnknownMessage([
        Ump([
          0x10000000 |
              status << 16 |
              (data.isNotEmpty ? data[0] << 8 : 0) |
              (data.length > 1 ? data[1] : 0),
        ]),
      ]);

  static bool _sameList(List<int>? a, List<int>? b) {
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
