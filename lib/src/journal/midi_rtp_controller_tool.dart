// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The tools a Chapter C controller log uses to code a Control Change
/// command (RFC 6295 A.3.2, Figures A.3.2 and A.3.3).
///
/// When several tools code one command, their logs follow each other in
/// the order of this enum: count, value, toggle (RFC 6295 A.3.3).
enum MidiRtpControllerTool {
  /// The count tool (A = 1, T = 1): the 6-bit number of commands for the
  /// controller in the session history, modulo 64.
  count,

  /// The value tool (A = 0): the 7-bit controller value.
  value,

  /// The toggle tool (A = 1, T = 0): the 6-bit number of off/on toggles of
  /// the controller in the session history, modulo 64.
  toggle;

  // ...........................................................................
  /// The largest value the tool codes: 127 for the value tool, 63 for the
  /// others.
  int get max => this == value ? 0x7F : 0x3F;
}
