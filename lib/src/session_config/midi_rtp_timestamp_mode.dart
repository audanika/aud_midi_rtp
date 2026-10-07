// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The semantics of the command timestamps of a stream, the values of the
/// tsmode parameter (RFC 6295 C.3).
enum MidiRtpTimestampMode {
  /// A timestamp codes the execution time of its command (RFC 6295 C.3.1),
  /// the default.
  comex,

  /// A timestamp codes the arrival of an octet of a time-of-arrival source,
  /// sampled asynchronously (RFC 6295 C.3.2).
  async,

  /// A timestamp codes the moment a buffer of a time-of-arrival source was
  /// examined, sampled synchronously (RFC 6295 C.3.3).
  buffer;

  // ...........................................................................
  /// Returns the mode of the tsmode [token].
  ///
  /// Throws a [FormatException] for unknown tokens.
  static MidiRtpTimestampMode fromToken(String token) => values.firstWhere(
    (mode) => mode.name == token,
    orElse: () => throw FormatException('Unknown tsmode value', token),
  );
}
