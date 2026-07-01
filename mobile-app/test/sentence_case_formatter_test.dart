import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_tracker/core/utils/text_formatters.dart';

TextEditingValue _committed(String t) =>
    TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));

// Mimics a soft keyboard mid-word: an active (non-collapsed) composing region.
TextEditingValue _composing(String t) => TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
      composing: TextRange(start: 0, end: t.length),
    );

void main() {
  const f = SentenceCaseInputFormatter();
  String apply(TextEditingValue v) =>
      f.formatEditUpdate(const TextEditingValue(), v).text;

  group('committed text / paste is capitalized', () {
    test('first letter', () => expect(apply(_committed('hello')), 'Hello'));
    test('after sentence end', () {
      expect(apply(_committed('hello world. it works! great? yes')),
          'Hello world. It works! Great? Yes');
    });
    test('after newline',
        () => expect(apply(_committed('line one\nline two')), 'Line one\nLine two'));
    test('preserves iPhone',
        () => expect(apply(_committed('my iPhone is here')), 'My iPhone is here'));
  });

  test('steps aside while composing (lets native auto-cap run)', () {
    // Must return the text UNCHANGED during composition so iOS does not revert.
    expect(apply(_composing('hello')), 'hello');
  });
}
