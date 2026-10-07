// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The value of one RPN or NRPN parameter as Chapter M protects it, with
/// the extended sequence number and the order of its most recent
/// transaction (RFC 6295 A.4).
typedef MidiRtpParameterValue = ({
  bool nrpn,
  int number,
  int seq,
  int order,
  ({int value, bool x, int seq})? entryMsb,
  ({int value, bool x, int seq})? entryLsb,
  ({int count, bool x, int seq})? aButton,
  int cButton,
});

// #############################################################################
/// The parameter system of one MIDI channel: RPN and NRPN selection,
/// transactions and parameter values, as the recovery journal sees them
/// (RFC 6295 A.1 "Parameter system transaction", A.3.4, A.4).
///
/// Control changes 98 to 101 always select parameters; 6, 38, 96 and 97
/// belong to a transaction while a parameter is selected and are
/// general-purpose controllers otherwise. A lone MSB (type 3 variant)
/// selects the LSB 0; a lone LSB (type 2 variant) takes the most recent
/// C-active MSB. Reset All Controllers closes the selection but keeps the
/// values (RP-015).
final class MidiRtpParameterState {
  /// Creates an empty parameter system.
  MidiRtpParameterState();

  // ...........................................................................
  /// Returns whether a Control Change of [controller] is a parameter system
  /// transaction command in the current state.
  bool handles(int controller) =>
      (controller >= 98 && controller <= 101) ||
      (_selection != null &&
          (controller == 6 ||
              controller == 38 ||
              controller == 96 ||
              controller == 97));

  /// Applies a transaction Control Change of [controller] with [value]
  /// from the packet [seq]; [order] ranks it in the session history.
  void apply(int controller, int value, {int seq = 0, int order = 0}) {
    switch (controller) {
      case 99 || 101:
        final nrpn = controller == 99;
        if (nrpn) {
          _lastNrpnMsb = value;
        } else {
          _lastRpnMsb = value;
        }
        _selection = (nrpn: nrpn, number: value << 7);
        _pendingSelection = true;
        _last = (kind: _Kind.msb, nrpn: nrpn, value: value, seq: seq);
      case 98 || 100:
        final nrpn = controller == 98;
        final number = ((nrpn ? _lastNrpnMsb : _lastRpnMsb) ?? 0) << 7 | value;
        _pendingSelection = false;
        if (number == 0x3FFF) {
          _selection = null;
          _last = (kind: _Kind.nullLsb, nrpn: nrpn, value: value, seq: seq);
        } else {
          _selection = (nrpn: nrpn, number: number);
          _initiate(seq, order);
          _last = (kind: _Kind.lsb, nrpn: nrpn, value: value, seq: seq);
        }
      default:
        _applyData(controller, value, seq, order);
    }
  }

  /// Applies a Reset All Controllers: the selection closes, Data Increment
  /// counts restart for C-BUTTON, values stay (RFC 6295 A.4.2, RP-015).
  void resetAllControllers() {
    _selection = null;
    _pendingSelection = false;
    _lastRpnMsb = null;
    _lastNrpnMsb = null;
    _last = null;
    for (final parameter in _parameters.values) {
      parameter.resetAllControllers();
    }
  }

  /// Applies a Reset State command: everything returns to power-up.
  void reset() {
    resetAllControllers();
    _parameters.clear();
  }

  // ...........................................................................
  /// Returns the value of a parameter, or null when no transaction set it.
  MidiRtpParameterValue? parameter({required bool nrpn, required int number}) =>
      _parameters[_key(nrpn, number)]?.value;

  /// The parameters with a transaction in the session history, oldest
  /// transaction first.
  List<MidiRtpParameterValue> get parameters =>
      (_parameters.values.map((p) => p.value).toList()
        ..sort((a, b) => a.order.compareTo(b.order)));

  /// The selected parameter, or null without selection; [pending] tells
  /// that only its MSB was sent.
  ({bool nrpn, int number, bool pending})? get selection => _selection == null
      ? null
      : (
          nrpn: _selection!.nrpn,
          number: _selection!.number,
          pending: _pendingSelection,
        );

  /// The PENDING field: the most recent C-active transaction command is
  /// the RPN or NRPN MSB with this value (Chapter M P bit).
  ({int value, bool nrpn})? get pending => _last?.kind == _Kind.msb
      ? (value: _last!.value, nrpn: _last!.nrpn)
      : null;

  /// The Chapter M E bit: an initiated transaction is in progress.
  bool get inProgress =>
      _last != null && _last!.kind != _Kind.msb && _last!.kind != _Kind.nullLsb;

  /// The packet of the most recent C-active transaction command when it is
  /// an MSB or completes the null parameter, which makes Chapter M
  /// required (RFC 6295 A.4).
  int? get selectionSeq =>
      _last != null &&
          (_last!.kind == _Kind.msb || _last!.kind == _Kind.nullLsb)
      ? _last!.seq
      : null;

  /// Returns the rendered state: the selection and the parameter values as
  /// `[msb, lsb, buttons]` keyed `rpn:<n>` or `nrpn:<n>`.
  Map<String, Object?> snapshot() => {
    'selection': _selection == null
        ? null
        : '${_selection!.nrpn ? 'nrpn' : 'rpn'}:${_selection!.number}'
              '${_pendingSelection ? '?' : ''}',
    'values': {
      for (final p in parameters)
        if (p.entryMsb != null ||
            p.entryLsb != null ||
            (p.aButton?.count ?? 0) != 0)
          '${p.nrpn ? 'nrpn' : 'rpn'}:${p.number}': [
            p.entryMsb?.value,
            p.entryLsb?.value,
            p.aButton?.count ?? 0,
          ],
    },
  };

  // ...........................................................................
  ({bool nrpn, int number})? _selection;
  bool _pendingSelection = false;
  int? _lastRpnMsb;
  int? _lastNrpnMsb;
  ({_Kind kind, bool nrpn, int value, int seq})? _last;
  final Map<int, _Parameter> _parameters = {};

  static int _key(bool nrpn, int number) => (nrpn ? 0x4000 : 0) | number;

  _Parameter _initiate(int seq, int order) {
    final selection = _selection!;
    final parameter = _parameters.putIfAbsent(
      _key(selection.nrpn, selection.number),
      () => _Parameter(selection.nrpn, selection.number),
    );
    parameter
      ..seq = seq
      ..order = order;
    return parameter;
  }

  void _applyData(int controller, int value, int seq, int order) {
    _pendingSelection = false;
    final parameter = _initiate(seq, order);
    final nrpn = _selection!.nrpn;
    _last = (kind: _Kind.data, nrpn: nrpn, value: value, seq: seq);
    switch (controller) {
      case 6:
        parameter
          ..entryMsb = (value: value, x: false, seq: seq)
          ..entryLsb = null
          ..clearButtons();
      case 38:
        parameter
          ..entryLsb = (value: value, x: false, seq: seq)
          ..clearButtons();
      default:
        parameter.press(controller == 96 ? 1 : -1, seq);
    }
  }
}

// #############################################################################
enum _Kind { msb, lsb, nullLsb, data }

// #############################################################################
class _Parameter {
  _Parameter(this.nrpn, this.number);

  final bool nrpn;
  final int number;
  int seq = 0;
  int order = 0;
  ({int value, bool x, int seq})? entryMsb;
  ({int value, bool x, int seq})? entryLsb;
  ({int count, bool x, int seq})? aButton;
  int cButton = 0;

  MidiRtpParameterValue get value => (
    nrpn: nrpn,
    number: number,
    seq: seq,
    order: order,
    entryMsb: entryMsb,
    entryLsb: entryLsb,
    aButton: aButton,
    cButton: cButton,
  );

  void clearButtons() {
    aButton = null;
    cButton = 0;
  }

  void press(int step, int seq) {
    final count = ((aButton?.count ?? 0) + step).clamp(-0x3FFF, 0x3FFF);
    aButton = (count: count, x: false, seq: seq);
    cButton = (cButton + step).clamp(-0x3FFF, 0x3FFF);
  }

  void resetAllControllers() {
    if (entryMsb case final e?) {
      entryMsb = (value: e.value, x: true, seq: e.seq);
    }
    if (entryLsb case final e?) {
      entryLsb = (value: e.value, x: true, seq: e.seq);
    }
    if (aButton case final a?) {
      aButton = (count: a.count, x: true, seq: a.seq);
    }
    cButton = 0;
  }
}
