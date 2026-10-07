// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:aud_midi_standard/aud_midi_standard.dart';

import 'midi_rtp_parameter_state.dart';

// #############################################################################
/// The most recent N-active note command of a note number (Chapters N and
/// E, RFC 6295 A.6, A.7).
typedef MidiRtpNoteValue = ({
  bool on,
  int velocity,
  int releaseVelocity,
  int count,
  int seq,
  int order,
  MidiTime time,
});

// #############################################################################
/// The most recent active Control Change of a controller number with its
/// tool values (Chapter C, RFC 6295 A.3).
typedef MidiRtpControllerValue = ({
  int value,
  int count,
  int toggles,
  int seq,
  int order,
});

// #############################################################################
/// The MIDI state of one voice channel as the recovery journal protects it:
/// the session history of the channel reduced to the most recent commands
/// per chapter, tagged with the extended sequence number of their packet
/// (RFC 6295 A.1 to A.9).
///
/// The state serves the sender as session history, the receiver as its
/// model of the stream and tests as a renderer. It follows the activity
/// rules of RFC 6295 A.1: Reset State commands clear everything,
/// controllers 120 and 123 to 127 end the N-activity of note and channel
/// pressure commands, and controller 121 ends the C-activity of pitch
/// wheel, pressure and parameter selection. Reset All Controllers resets
/// the rendered values of RP-015: modulation 0, expression 127, pedals 64
/// to 67 off, pitch wheel center, pressures 0.
final class MidiRtpChannelState {
  /// Creates the state of [channel]; the controllers in
  /// [enhancedControllers] keep every command for the enhanced Chapter C
  /// encoding (RFC 6295 A.3.3).
  MidiRtpChannelState({
    required this.channel,
    Set<int> enhancedControllers = const {},
  }) : _enhanced = enhancedControllers;

  // ...........................................................................
  /// Applies [message] of the packet [seq] at [time]; [order] ranks it in
  /// the session history.
  void apply(
    MidiChannelVoice1Message message, {
    int seq = 0,
    int order = 0,
    MidiTime time = MidiTime.zero,
  }) {
    switch (message) {
      case MidiNoteOn(:final note, :final velocity) when velocity > 0:
        final value = _notes[note];
        _notes[note] = (
          on: true,
          velocity: velocity,
          releaseVelocity: value?.releaseVelocity ?? 64,
          count: (value?.count ?? 0) + 1,
          seq: seq,
          order: order,
          time: time,
        );
      case MidiNoteOn(:final note):
        _noteOff(note, 64, seq, order);
      case MidiNoteOff(:final note, :final velocity):
        _noteOff(note, velocity, seq, order);
      case MidiPolyPressure(:final note, :final pressure):
        _polyPressure[note] = (
          value: pressure,
          x: false,
          seq: seq,
          order: order,
        );
        _renderedPolyPressure[note] = pressure;
      case MidiControlChange(:final controller, :final value):
        _control(controller, value, seq, order);
      case MidiProgramChange(:final program):
        final bank = _bankMsb != null;
        _program = (
          program: program,
          b: bank,
          bankMsb: _bankMsb ?? 0,
          x: bank && _resetSinceBankMsb,
          bankLsb: bank ? _bankLsb ?? 0 : 0,
          seq: seq,
        );
      case MidiChannelPressure(:final pressure):
        _channelPressure = (value: pressure, seq: seq);
        _renderedChannelPressure = pressure;
      case MidiPitchBend(:final value):
        _pitchWheel = (value: value, seq: seq);
        _renderedPitchWheel = value;
    }
  }

  /// Applies a Reset State command: the channel returns to power-up.
  void reset() {
    _notes.clear();
    _noteOffSeq = null;
    _controllers.clear();
    _history.clear();
    _toggles.clear();
    _counts.clear();
    _rendered.clear();
    _program = null;
    _bankMsb = null;
    _bankLsb = null;
    _resetSinceBankMsb = false;
    _pitchWheel = null;
    _renderedPitchWheel = null;
    _channelPressure = null;
    _renderedChannelPressure = null;
    _polyPressure.clear();
    _renderedPolyPressure.clear();
    parameterSystem.reset();
  }

  /// Drops enhanced Chapter C commands before [checkpoint], except for the
  /// controllers [keep] selects.
  void trim(int checkpoint, {bool Function(int controller)? keep}) {
    for (final entry in _history.entries) {
      if (keep?.call(entry.key) ?? false) continue;
      entry.value.removeWhere((command) => command.seq < checkpoint);
    }
  }

  // ...........................................................................
  /// Returns the most recent N-active note command of [note], or null.
  MidiRtpNoteValue? note(int note) => _notes[note];

  /// Sets the reference count of [note] (Chapter E) after a repair.
  void setNoteCount(int note, int count) {
    final value = _notes[note];
    if (value != null) {
      _notes[note] = (
        on: value.on,
        velocity: value.velocity,
        releaseVelocity: value.releaseVelocity,
        count: count,
        seq: value.seq,
        order: value.order,
        time: value.time,
      );
    }
  }

  /// Returns the most recent active command of [controller], or null.
  ///
  /// Commands that belong to a parameter system transaction are not
  /// controller commands (RFC 6295 A.3.4).
  MidiRtpControllerValue? controller(int controller) =>
      _controllers[controller];

  /// Returns the commands of an enhanced [controller] kept for Chapter C,
  /// oldest first.
  List<MidiRtpControllerValue> controllerHistory(int controller) =>
      List.unmodifiable(_history[controller] ?? const []);

  /// Returns the count tool value of [controller]: its commands since the
  /// last Reset State, modulo 64.
  int controllerCount(int controller) => _counts[controller] ?? 0;

  /// Returns the toggle tool value of [controller]: its off/on toggles
  /// since the last Reset State, modulo 64.
  int controllerToggles(int controller) =>
      _toggles[controller] ?? (_defaultOn(controller) ? 1 : 0);

  /// Sets the tool values of the most recent command of [controller] after
  /// a repair: its [count] and its [toggles].
  ///
  /// The count of the stream equals the count of the most recent command;
  /// the toggle count of the stream keeps its offset from the command's,
  /// the toggles of later Reset All Controllers.
  void setControllerTools(int controller, {int? count, int? toggles}) {
    final command = _controllers[controller];
    if (count != null) _counts[controller] = count & 0x3F;
    if (toggles != null) {
      final current = controllerToggles(controller);
      final offset = current - (command?.toggles ?? current);
      _toggles[controller] = (toggles + offset) & 0x3F;
    }
    if (command != null) {
      _controllers[controller] = (
        value: command.value,
        count: count == null ? command.count : count & 0x3F,
        toggles: toggles == null ? command.toggles : toggles & 0x3F,
        seq: command.seq,
        order: command.order,
      );
    }
  }

  /// Returns the rendered value of [controller], or null when unknown.
  int? controllerValue(int controller) => _rendered[controller];

  // ...........................................................................
  /// The MIDI channel.
  final int channel;

  /// The RPN/NRPN parameter system of the channel (Chapter M).
  final MidiRtpParameterState parameterSystem = MidiRtpParameterState();

  /// The packet of the most recent NoteOff, for the B bit of Chapter N.
  int? get noteOffSeq => _noteOffSeq;

  /// The most recent active Program Change with its bank (Chapter P).
  ({int program, bool b, int bankMsb, bool x, int bankLsb, int seq})?
  get program => _program;

  /// The Bank Select registers a Program Change would use: the most recent
  /// active Bank Select MSB and the Bank Select LSB that followed it.
  ({int? msb, int? lsb}) get bank => (msb: _bankMsb, lsb: _bankLsb);

  /// The most recent C-active Pitch Wheel (Chapter W).
  ({int value, int seq})? get pitchWheel => _pitchWheel;

  /// The most recent N-active and C-active Channel Aftertouch (Chapter T).
  ({int value, int seq})? get channelPressure => _channelPressure;

  /// Returns the most recent C-active Poly Aftertouch of [note] (Chapter
  /// A); x tells that it came before an All Notes Off.
  ({int value, bool x, int seq, int order})? polyPressure(int note) =>
      _polyPressure[note];

  /// The note numbers with an N-active note command, by ascending order.
  List<int> get notes =>
      (_notes.keys.toList()
        ..sort((a, b) => _notes[a]!.order.compareTo(_notes[b]!.order)));

  /// The controller numbers with an active command, by ascending order.
  List<int> get controllers => (_controllers.keys.toList()
    ..sort((a, b) => _controllers[a]!.order.compareTo(_controllers[b]!.order)));

  /// The note numbers with a C-active Poly Aftertouch, by ascending order.
  List<int> get polyPressureNotes => (_polyPressure.keys.toList()
    ..sort(
      (a, b) => _polyPressure[a]!.order.compareTo(_polyPressure[b]!.order),
    ));

  /// Whether a note of the channel sounds: its most recent N-active
  /// command is a NoteOn.
  bool get hasSoundingNotes => _notes.values.any((note) => note.on);

  // ...........................................................................
  /// Returns the rendered state of the channel for comparisons, or an empty
  /// map for a channel at power-up.
  Map<String, Object?> snapshot() {
    final notes = {
      for (final n in _notes.keys.toList()..sort())
        if (_notes[n]!.on) n: _notes[n]!.velocity,
    };
    final controllers = {
      for (final c in _rendered.keys.toList()..sort())
        if (!_actions.contains(c)) c: _rendered[c],
    };
    final poly = {
      for (final n in _renderedPolyPressure.keys.toList()..sort())
        if (_renderedPolyPressure[n] != 0) n: _renderedPolyPressure[n],
    };
    final parameters = parameterSystem.snapshot();
    final pitchWheel = _renderedPitchWheel ?? MidiPitchBend.center;
    final pressure = _renderedChannelPressure == 0
        ? null
        : _renderedChannelPressure;
    return {
      if (notes.isNotEmpty) 'notes': notes,
      if (controllers.isNotEmpty) 'controllers': controllers,
      if (_program != null)
        'program': [
          _program!.program,
          if (_program!.b) ...[_program!.bankMsb, _program!.bankLsb],
        ],
      if (pitchWheel != MidiPitchBend.center) 'pitchWheel': pitchWheel,
      'channelPressure': ?pressure,
      if (poly.isNotEmpty) 'polyPressure': poly,
      if (parameters['selection'] != null ||
          (parameters['values']! as Map).isNotEmpty)
        'parameters': parameters,
    };
  }

  // ...........................................................................
  final Set<int> _enhanced;
  final Map<int, MidiRtpNoteValue> _notes = {};
  int? _noteOffSeq;
  final Map<int, MidiRtpControllerValue> _controllers = {};
  final Map<int, List<MidiRtpControllerValue>> _history = {};
  final Map<int, int> _counts = {};
  final Map<int, int> _toggles = {};
  final Map<int, int> _rendered = {};
  ({int program, bool b, int bankMsb, bool x, int bankLsb, int seq})? _program;
  int? _bankMsb;
  int? _bankLsb;
  bool _resetSinceBankMsb = false;
  ({int value, int seq})? _pitchWheel;
  int? _renderedPitchWheel;
  ({int value, int seq})? _channelPressure;
  int? _renderedChannelPressure;
  final Map<int, ({int value, bool x, int seq, int order})> _polyPressure = {};
  final Map<int, int> _renderedPolyPressure = {};

  /// The controllers that only act and carry no state: All Sound Off, Reset
  /// All Controllers, All Notes Off and the parameter number controllers.
  static const Set<int> _actions = {98, 99, 100, 101, 120, 121, 123};

  /// The controllers whose default value is 64 or more, so their toggle
  /// count starts at 1 (RFC 6295 A.3.2).
  static const Set<int> _defaultOnControllers = {
    7, 8, 10, 11, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, //
  };

  static bool _defaultOn(int controller) =>
      _defaultOnControllers.contains(controller);

  void _noteOff(int note, int velocity, int seq, int order) {
    final value = _notes[note];
    _notes[note] = (
      on: false,
      velocity: value?.velocity ?? 0,
      releaseVelocity: velocity,
      count: (value?.count ?? 0) > 0 ? value!.count - 1 : 0,
      seq: seq,
      order: order,
      time: value?.time ?? MidiTime.zero,
    );
    _noteOffSeq = seq;
  }

  void _control(int controller, int value, int seq, int order) {
    if (parameterSystem.handles(controller)) {
      parameterSystem.apply(controller, value, seq: seq, order: order);
      return;
    }
    final count = (controllerCount(controller) + 1) & 0x3F;
    _counts[controller] = count;
    _render(controller, value);
    final command = (
      value: value,
      count: count,
      toggles: controllerToggles(controller),
      seq: seq,
      order: order,
    );
    _controllers[controller] = command;
    if (_enhanced.contains(controller)) {
      (_history[controller] ??= []).add(command);
    }
    switch (controller) {
      case 0:
        _bankMsb = value;
        _bankLsb = null;
        _resetSinceBankMsb = false;
      case 32:
        _bankLsb = value;
      case 121:
        _resetAllControllers();
      case 120 || 123 || 124 || 125 || 126 || 127:
        _allNotesOff();
    }
  }

  void _render(int controller, int value) {
    final before = _rendered[controller];
    final wasOn = before == null ? _defaultOn(controller) : before >= 64;
    if (wasOn != value >= 64) {
      _toggles[controller] = (controllerToggles(controller) + 1) & 0x3F;
    }
    _rendered[controller] = value;
  }

  void _resetAllControllers() {
    _render(1, 0);
    _render(11, 127);
    for (var pedal = 64; pedal <= 67; pedal++) {
      _render(pedal, 0);
    }
    _pitchWheel = null;
    _renderedPitchWheel = MidiPitchBend.center;
    _channelPressure = null;
    _renderedChannelPressure = 0;
    _polyPressure.clear();
    _renderedPolyPressure.clear();
    if (_bankMsb != null) _resetSinceBankMsb = true;
    parameterSystem.resetAllControllers();
  }

  void _allNotesOff() {
    _notes.clear();
    _channelPressure = null;
    _renderedChannelPressure = null;
    for (final entry in _polyPressure.entries.toList()) {
      final p = entry.value;
      _polyPressure[entry.key] = (
        value: p.value,
        x: true,
        seq: p.seq,
        order: p.order,
      );
    }
  }
}
