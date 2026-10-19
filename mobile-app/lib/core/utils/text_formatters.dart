import 'package:flutter/services.dart';

/// Capitalisation formatters that enforce casing for committed text and pastes
/// — a fallback for cases `textCapitalization` doesn't cover (hardware
/// keyboards like the iOS Simulator, and pasted text).
///
/// IMPORTANT: while the soft keyboard is actively composing a word (iOS
/// autocorrect / predictive text), these formatters STEP ASIDE. Rewriting the
/// value mid-composition and clearing the composing region makes iOS revert
/// the change on the next keystroke, which left note text stuck in lowercase.
/// During composition we let the field's native `textCapitalization` and
/// autocorrect do the work (that is also what capitalises proper nouns / "I"
/// for correct grammar); the formatter only kicks in once text is committed.
///
/// Both formatters only ever upper-case selected positions; they never
/// lower-case what the user typed, so intentional casing inside a word
/// (e.g. "McDonald", "iPhone") is preserved. Output length always matches the
/// input, so the caret/selection stays valid.

final _letter = RegExp(r'[A-Za-z]');

/// True while the IME holds an active (non-empty) composing region — i.e. the
/// soft keyboard is mid-word. Formatters must not rewrite text in this state.
bool _isComposing(TextEditingValue v) =>
    v.composing.isValid && !v.composing.isCollapsed;

/// Capitalises the first letter of every sentence: the first letter overall,
/// and the first letter following a `.`, `!`, or `?` (after any spaces) or a
/// line break. Mirrors `TextCapitalization.sentences`, but actually applied.
class SentenceCaseInputFormatter extends TextInputFormatter {
  const SentenceCaseInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Don't fight the soft keyboard mid-word; native auto-cap/autocorrect run.
    if (_isComposing(newValue)) return newValue;
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final out = StringBuffer();
    var capNext = true; // capitalise the very first letter
    // saw . ! ? — capitalise the next letter that follows a space
    var pendingPunct = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\n') {
        out.write(ch);
        capNext = true;
        pendingPunct = false;
      } else if (ch == ' ' || ch == '\t') {
        out.write(ch);
        if (pendingPunct) {
          capNext = true;
          pendingPunct = false;
        }
      } else if (ch == '.' || ch == '!' || ch == '?') {
        out.write(ch);
        pendingPunct = true;
      } else if (_letter.hasMatch(ch)) {
        out.write(capNext ? ch.toUpperCase() : ch);
        capNext = false;
        pendingPunct = false;
      } else {
        out.write(ch);
        pendingPunct = false;
      }
    }

    final result = out.toString();
    if (result == text) return newValue;
    return TextEditingValue(
      text: result,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Sentence case plus a closing period for talk-to-text notes.
/// Also turns spoken punctuation ("period", "comma", "question mark") into marks.
String formatProfessionalNotes(String raw, {bool closingPeriod = true}) {
  var text = applySpokenPunctuation(raw.trim());
  if (text.isEmpty) return text;
  text = text.replaceAllMapped(
    RegExp(r'\bi\b'),
    (m) => 'I',
  );
  final buf = StringBuffer();
  var capNext = true;
  var pendingPunct = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '\n') {
      buf.write(ch);
      capNext = true;
      pendingPunct = false;
    } else if (ch == ' ' || ch == '\t') {
      buf.write(ch);
      if (pendingPunct) {
        capNext = true;
        pendingPunct = false;
      }
    } else if (ch == '.' || ch == '!' || ch == '?') {
      buf.write(ch);
      pendingPunct = true;
    } else if (_letter.hasMatch(ch)) {
      buf.write(capNext ? ch.toUpperCase() : ch);
      capNext = false;
      pendingPunct = false;
    } else {
      buf.write(ch);
      pendingPunct = false;
    }
  }
  text = buf.toString();
  text = text.replaceAll(RegExp(r' +'), ' ').trim();
  text = text.replaceAllMapped(
    RegExp(r' +([,.;:!?])'),
    (m) => m.group(1)!,
  );
  if (closingPeriod &&
      text.isNotEmpty &&
      !RegExp(r'[.!?]$').hasMatch(text)) {
    text = '$text.';
  }
  return text;
}

/// Maps dictated punctuation phrases to real marks (Coursera-style dictation).
String applySpokenPunctuation(String raw) {
  if (raw.isEmpty) return raw;
  var text = ' $raw ';
  const replacements = <String, String>{
    ' new paragraph ': '\n\n',
    ' new line ': '\n',
    ' next line ': '\n',
    ' question mark ': '? ',
    ' exclamation point ': '! ',
    ' exclamation mark ': '! ',
    ' full stop ': '. ',
    ' period ': '. ',
    ' semicolon ': '; ',
    ' colon ': ': ',
    ' comma ': ', ',
  };
  for (final e in replacements.entries) {
    text = text.replaceAll(
      RegExp(e.key, caseSensitive: false),
      e.value,
    );
  }
  return text.trim();
}

/// Capitalises the first letter of every word — for names. Word boundaries are
/// whitespace plus `-` and `/` (so "mary-jane" → "Mary-Jane"). Mirrors
/// `TextCapitalization.words`, but actually applied.
class TitleCaseInputFormatter extends TextInputFormatter {
  const TitleCaseInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Don't fight the soft keyboard mid-word; native auto-cap/autocorrect run.
    if (_isComposing(newValue)) return newValue;
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final out = StringBuffer();
    var capNext = true;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '-' || ch == '/') {
        out.write(ch);
        capNext = true;
      } else if (_letter.hasMatch(ch)) {
        out.write(capNext ? ch.toUpperCase() : ch);
        capNext = false;
      } else {
        out.write(ch);
        capNext = false;
      }
    }

    final result = out.toString();
    if (result == text) return newValue;
    return TextEditingValue(
      text: result,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
