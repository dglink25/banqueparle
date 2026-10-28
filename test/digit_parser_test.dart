import 'package:flutter_test/flutter_test.dart';
import 'package:banqueparle/utils/digit_parser.dart';

void main() {
  group('DigitParser Tests - Numbers 1, 2, 4 and all digits', () {
    test('recognizes standard digits and words', () {
      expect(extractDigits('1'), '1');
      expect(extractDigits('2'), '2');
      expect(extractDigits('4'), '4');
      expect(extractDigits('un'), '1');
      expect(extractDigits('deux'), '2');
      expect(extractDigits('quatre'), '4');
    });

    test('recognizes homophones and ordinals for 1 and 2', () {
      expect(extractDigits('une'), '1');
      expect(extractDigits('premier'), '1');
      expect(extractDigits('1er'), '1');
      expect(extractDigits('hein'), '1');
      expect(extractDigits('de'), '2');
      expect(extractDigits('des'), '2');
      expect(extractDigits('second'), '2');
      expect(extractDigits('deuxième'), '2');
      expect(extractDigits('2e'), '2');
    });

    test('handles zero with and without accent', () {
      expect(extractDigits('zéro'), '0');
      expect(extractDigits('zero'), '0');
    });

    test('extracts sequence of digits', () {
      expect(extractDigits('un deux trois quatre'), '1234');
      expect(extractDigits('1 2 4'), '124');
    });
  });
}
