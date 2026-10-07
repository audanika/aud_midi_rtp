// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import '../payload/midi_rtp_sys_ex_kind.dart';
import 'midi_rtp_sys_ex_status.dart';
import 'midi_rtp_time_code.dart';

// #############################################################################
/// A System Exclusive command of the session history as Chapter X codes it
/// (RFC 6295 B.5): its data octets so far, its status, the COUNT after it
/// entered the history, the packets that carried its octets (`chunks`: the
/// packet and the index of its first octet), the packet of its most recent
/// segment and its order.
typedef MidiRtpSysExValue = ({
  List<int> data,
  MidiRtpSysExStatus status,
  int count,
  List<({int seq, int offset})> chunks,
  int seq,
  int order,
  bool fullFrame,
});

// #############################################################################
/// The system command state of an RTP MIDI stream as the system journal
/// protects it (RFC 6295 B.1 to B.5): reference counts of Reset, Tune
/// Request and Active Sense, Song Select, the undefined commands, the
/// sequencer, MIDI Time Code and System Exclusive.
///
/// Values carry the extended sequence number of their packet. Reset State
/// commands end the activity of everything but the reference counts.
final class MidiRtpSystemState {
  /// Creates the state; [countsSysEx] excludes System Exclusive commands
  /// from the Chapter X COUNT, e.g. those assigned to ch_never.
  MidiRtpSystemState({this._countsSysEx});

  // ...........................................................................
  /// Applies a system common or real-time [message] of the packet [seq];
  /// [order] ranks it in the session history.
  ///
  /// A System Reset only counts here; the stream resets the state.
  void apply(MidiSystemMessage message, {int seq = 0, int order = 0}) {
    switch (message) {
      case MidiSystemReset():
        _resetCount = (_resetCount + 1) & 0x7F;
        _resetSeq = seq;
      case MidiTuneRequest():
        _tuneRequestCount = (_tuneRequestCount + 1) & 0x7F;
        _tuneRequestSeq = seq;
      case MidiSongSelect(:final song):
        _songSelect = (value: song, seq: seq);
      case MidiActiveSensing():
        _activeSenseCount = (_activeSenseCount + 1) & 0x7F;
        _activeSenseSeq = seq;
      case MidiTimeCodeQuarterFrame(:final piece, :final value):
        _quarterFrame(piece, value, seq);
      case MidiTimingClock() ||
          MidiStart() ||
          MidiContinue() ||
          MidiStop() ||
          MidiSongPositionPointer():
        _sequence(message, seq);
    }
  }

  /// Applies a System Exclusive command or segment of [kind] with [data]
  /// from the packet [seq] and returns the data of the command it
  /// completes, or null.
  ///
  /// - [droppedF7] the command ended without 0xF7.
  /// - [count] whether the command counts for the Chapter X COUNT; a
  ///   receiver that repairs a time code from Chapter F does not count it.
  List<int>? applySysEx(
    MidiRtpSysExKind kind,
    List<int> data, {
    bool droppedF7 = false,
    int seq = 0,
    int order = 0,
    bool count = true,
  }) {
    if (kind.startsCommand) {
      final counted = count && (_countsSysEx?.call(data) ?? true);
      if (counted) _sysExCount = (_sysExCount + 1) & 0xFF;
      _current = _SysEx(data, _sysExCount, seq, order);
      _records.add(_current!);
    } else {
      final current = _current;
      if (current == null) return null;
      current.append(data, seq);
    }
    final current = _current!;
    switch (kind) {
      case MidiRtpSysExKind.first || MidiRtpSysExKind.middle:
        return null;
      case MidiRtpSysExKind.cancel:
        current.status = MidiRtpSysExStatus.cancelled;
        _current = null;
        return null;
      case MidiRtpSysExKind.complete || MidiRtpSysExKind.last:
        current.status = droppedF7
            ? MidiRtpSysExStatus.droppedF7
            : MidiRtpSysExStatus.finished;
        _current = null;
        _finished(current);
        return List.unmodifiable(current.data);
    }
  }

  /// Applies a Full Frame time code [code] from the packet [seq] to the
  /// time code state only, without a System Exclusive record: a receiver
  /// relocates the time code from Chapter F this way, even while a
  /// segmented System Exclusive command is in progress.
  void locate(MidiRtpTimeCode code, {int seq = 0}) {
    _completeFrame = (field: code.toField(nibbles: false), q: false, seq: seq);
    _partialFrame = null;
    _lastPiece = null;
    _reverse = false;
    _timeCodeSeq = seq;
  }

  /// Applies an undefined system command with [status] 0xF4, 0xF5, 0xF9
  /// or 0xFD and its [data] from the packet [seq] (Chapter D).
  void applyUndefined(int status, List<int> data, {int seq = 0}) {
    final count = (undefinedCount(status) + 1) & 0xFF;
    _undefined[status] = (
      count: count,
      data: List.unmodifiable(data),
      seq: seq,
    );
  }

  /// Applies a Reset State command: the active state ends; the reference
  /// counts stay. [keepLastSysEx] keeps the System Exclusive command that
  /// is the Reset State command itself.
  void reset({bool keepLastSysEx = false}) {
    final last = keepLastSysEx ? _records.last : null;
    _resetSeq = null;
    _tuneRequestSeq = null;
    _songSelect = null;
    _activeSenseSeq = null;
    for (final status in _undefined.keys.toList()) {
      _undefined[status] = (
        count: _undefined[status]!.count,
        data: const [],
        seq: -1,
      );
    }
    _sequencer = _initialSequencer;
    _sequencerSeq = null;
    _completeFrame = null;
    _partialFrame = null;
    _lastPiece = null;
    _reverse = false;
    _timeCodeSeq = null;
    _records.clear();
    _current = null;
    _lastSysEx = null;
    if (last != null) {
      _records.add(last);
      _lastSysEx = last.data;
    }
  }

  /// Drops System Exclusive commands whose last segment came before
  /// [checkpoint], except the unfinished one and those [keep] selects.
  void trim(int checkpoint, {bool Function(List<int> data)? keep}) {
    _records.removeWhere(
      (r) =>
          r.seq < checkpoint &&
          !identical(r, _current) &&
          !(keep?.call(r.data) ?? false),
    );
  }

  /// Sets reference counts after a repair.
  void syncCounts({
    int? resetCount,
    int? tuneRequestCount,
    int? activeSenseCount,
    int? sysExCount,
  }) {
    if (resetCount != null) _resetCount = resetCount & 0x7F;
    if (tuneRequestCount != null) _tuneRequestCount = tuneRequestCount & 0x7F;
    if (activeSenseCount != null) _activeSenseCount = activeSenseCount & 0x7F;
    if (sysExCount != null) _sysExCount = sysExCount & 0xFF;
  }

  /// Sets the count of the undefined command [status] after a repair.
  void syncUndefinedCount(int status, int count) {
    final value = _undefined[status];
    _undefined[status] = (
      count: count & 0xFF,
      data: value?.data ?? const [],
      seq: value?.seq ?? -1,
    );
  }

  // ...........................................................................
  /// The number of System Reset commands modulo 128.
  int get resetCount => _resetCount;

  /// The packet of the most recent active System Reset.
  int? get resetSeq => _resetSeq;

  /// The number of Tune Request commands modulo 128.
  int get tuneRequestCount => _tuneRequestCount;

  /// The packet of the most recent active Tune Request.
  int? get tuneRequestSeq => _tuneRequestSeq;

  /// The most recent active Song Select.
  ({int value, int seq})? get songSelect => _songSelect;

  /// The number of Active Sense commands modulo 128.
  int get activeSenseCount => _activeSenseCount;

  /// The packet of the most recent active Active Sense.
  int? get activeSenseSeq => _activeSenseSeq;

  /// Returns the number of undefined commands [status] modulo 256.
  int undefinedCount(int status) => _undefined[status]?.count ?? 0;

  /// Returns the most recent active undefined command [status]: its data
  /// and packet, or null.
  ({List<int> data, int seq})? undefined(int status) {
    final value = _undefined[status];
    return value == null || value.seq < 0
        ? null
        : (data: value.data, seq: value.seq);
  }

  /// The sequencer: running (N), downbeat (D), song position in clocks,
  /// whether Start is more recent than Continue (Chapter Q).
  ({bool running, bool downbeat, int position, bool startRecent})
  get sequencer => _sequencer;

  /// The packet of the most recent command that changed the sequencer.
  int? get sequencerSeq => _sequencerSeq;

  /// The most recent complete time code frame: the COMPLETE field and its
  /// format Q (Chapter F).
  ({int field, bool q, int seq})? get completeFrame => _completeFrame;

  /// The frame in progress: the PARTIAL field and its last valid message
  /// type, or null when the most recent Quarter Frame starts no partial
  /// frame.
  ({int field, int point})? get partialFrame => _partialFrame == null
      ? null
      : (
          field: _packNibbles(_partialFrame!.nibbles),
          point: _partialFrame!.point,
        );

  /// Whether the tape moves in reverse (Chapter F D bit).
  bool get reverse => _reverse;

  /// The packet of the most recent active MIDI Time Code command.
  int? get timeCodeSeq => _timeCodeSeq;

  /// The active System Exclusive commands in order.
  List<MidiRtpSysExValue> get sysEx => [for (final r in _records) r.value];

  /// The unfinished System Exclusive command, or null.
  MidiRtpSysExValue? get unfinishedSysEx => _current?.value;

  /// The number of System Exclusive commands modulo 256 (Chapter X COUNT).
  int get sysExCount => _sysExCount;

  // ...........................................................................
  /// Returns the rendered state: song, sequencer, time code and the most
  /// recent complete System Exclusive, without reference counts.
  Map<String, Object?> snapshot() {
    final timeCode = _completeFrame == null
        ? null
        : MidiRtpTimeCode.fromField(
            _completeFrame!.field,
            nibbles: _completeFrame!.q,
          ).toString();
    final partial = partialFrame;
    return {
      if (_songSelect != null) 'songSelect': _songSelect!.value,
      if (_sequencer.running || _sequencer.downbeat || _sequencer.position != 0)
        'sequencer': [
          _sequencer.running,
          _sequencer.position,
          _sequencer.downbeat,
        ],
      'timeCode': ?timeCode,
      if (partial != null)
        'partialTimeCode': [_reverse, partial.point, partial.field],
      if (_lastSysEx != null) 'sysEx': _lastSysEx,
    };
  }

  // ...........................................................................
  /// Returns whether [data] is a Full Frame MIDI Time Code message: F0 7F
  /// cc 01 01 hr mn sc fr F7.
  static bool isFullFrame(List<int> data) =>
      data.length == 8 && data[0] == 0x7F && data[2] == 0x01 && data[3] == 0x01;

  /// Returns whether [data] is a Reset State System Exclusive command: GM
  /// System Enable or Disable, GM2 System Enable, DLS On or Off (RFC 6295
  /// A.1).
  ///
  /// GM System Disable is listed as 09 00 in RFC 6295 and as 09 02 in the
  /// MIDI 1.0 specification; both count.
  static bool isResetState(List<int> data) =>
      data.length == 4 &&
      data[0] == 0x7E &&
      ((data[2] == 0x09 && data[3] <= 0x03) ||
          (data[2] == 0x0A && (data[3] == 0x01 || data[3] == 0x02)));

  // ...........................................................................
  final bool Function(List<int> data)? _countsSysEx;
  int _resetCount = 0;
  int? _resetSeq;
  int _tuneRequestCount = 0;
  int? _tuneRequestSeq;
  ({int value, int seq})? _songSelect;
  int _activeSenseCount = 0;
  int? _activeSenseSeq;
  final Map<int, ({int count, List<int> data, int seq})> _undefined = {};

  static const _initialSequencer = (
    running: false,
    downbeat: false,
    position: 0,
    startRecent: false,
  );
  ({bool running, bool downbeat, int position, bool startRecent}) _sequencer =
      _initialSequencer;
  int? _sequencerSeq;

  ({int field, bool q, int seq})? _completeFrame;
  ({List<int> nibbles, int point, bool forward})? _partialFrame;
  int? _lastPiece;
  bool _reverse = false;
  int? _timeCodeSeq;

  final List<_SysEx> _records = [];
  _SysEx? _current;
  int _sysExCount = 0;
  List<int>? _lastSysEx;

  void _finished(_SysEx record) {
    if (isFullFrame(record.data)) {
      record.fullFrame = true;
      locate(
        MidiRtpTimeCode.fromFullFrame(record.data.sublist(4)),
        seq: record.seq,
      );
    } else {
      _lastSysEx = List.unmodifiable(record.data);
    }
  }

  void _sequence(MidiSystemMessage message, int seq) {
    final s = _sequencer;
    final next = switch (message) {
      MidiStart() => (
        running: true,
        downbeat: false,
        position: 0,
        startRecent: true,
      ),
      MidiContinue() => (
        running: true,
        downbeat: s.downbeat,
        position: s.position,
        startRecent: false,
      ),
      MidiStop() => (
        running: false,
        downbeat: s.downbeat,
        position: s.position,
        startRecent: s.startRecent,
      ),
      MidiSongPositionPointer(:final position) => (
        running: s.running,
        downbeat: false,
        position: (position * 6) & 0x7FFFF,
        startRecent: s.startRecent,
      ),
      _ =>
        !s.running
            ? s
            : (
                running: true,
                downbeat: true,
                position: s.downbeat ? (s.position + 1) & 0x7FFFF : s.position,
                startRecent: s.startRecent,
              ),
    };
    if (next != s) {
      _sequencer = next;
      _sequencerSeq = seq;
    }
  }

  void _quarterFrame(int piece, int value, int seq) {
    _timeCodeSeq = seq;
    final last = _lastPiece;
    if (last != null && piece == (last + 1) % 8) _reverse = false;
    if (last != null && piece == (last + 7) % 8) _reverse = true;
    _lastPiece = piece;
    final run = _partialFrame;
    if (run != null && piece == run.point + (run.forward ? 1 : -1)) {
      run.nibbles[piece] = value;
      if (piece == (run.forward ? 7 : 0)) {
        _partialFrame = null;
        final code = MidiRtpTimeCode.fromNibbles(run.nibbles);
        _completeFrame = (
          field: run.forward
              ? code.advance(2).toField(nibbles: true)
              : _packNibbles(run.nibbles),
          q: true,
          seq: seq,
        );
      } else {
        _partialFrame = (
          nibbles: run.nibbles,
          point: piece,
          forward: run.forward,
        );
      }
    } else if (piece == 0 || piece == 7) {
      _reverse = piece == 7;
      _partialFrame = (
        nibbles: List.filled(8, 0)..[piece] = value,
        point: piece,
        forward: piece == 0,
      );
    } else {
      _partialFrame = null;
    }
  }

  static int _packNibbles(List<int> nibbles) =>
      nibbles.fold(0, (field, nibble) => field << 4 | nibble);
}

// #############################################################################
class _SysEx {
  _SysEx(List<int> data, this.count, this.seq, this.order)
    : data = [...data],
      chunks = [(seq: seq, offset: 0)];

  final List<int> data;
  final int count;
  final List<({int seq, int offset})> chunks;
  int seq;
  final int order;
  MidiRtpSysExStatus status = MidiRtpSysExStatus.unfinished;
  bool fullFrame = false;

  MidiRtpSysExValue get value => (
    data: List.unmodifiable(data),
    status: status,
    count: count,
    chunks: List.unmodifiable(chunks),
    seq: seq,
    order: order,
    fullFrame: fullFrame,
  );

  void append(List<int> octets, int seq) {
    if (seq != this.seq) chunks.add((seq: seq, offset: data.length));
    data.addAll(octets);
    this.seq = seq;
  }
}
