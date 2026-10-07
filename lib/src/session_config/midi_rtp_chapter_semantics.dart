// @license
// Copyright (c) Audanika
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// The inclusion semantics of a recovery journal chapter or chapter subset,
/// set by the chapter inclusion parameters (RFC 6295 C.2.3).
enum MidiRtpChapterSemantics {
  /// ch_never: the chapter never appears in the journal.
  never('ch_never'),

  /// ch_default: the chapter follows its definition in Appendices A and B.
  standard('ch_default'),

  /// ch_anchor: the chapter covers the session history instead of the
  /// checkpoint history, as if the first packet were the checkpoint.
  anchor('ch_anchor');

  /// Creates semantics with the name of their fmtp [parameter].
  const MidiRtpChapterSemantics(this.parameter);

  // ...........................................................................
  /// The fmtp parameter that assigns these semantics.
  final String parameter;

  // ...........................................................................
  /// Returns the semantics a [parameter] assigns, or null for other
  /// parameters.
  static MidiRtpChapterSemantics? ofParameter(String parameter) {
    for (final semantics in values) {
      if (semantics.parameter == parameter) return semantics;
    }
    return null;
  }
}
