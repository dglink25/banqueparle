import 'package:flutter_test/flutter_test.dart';
import 'package:banqueparle/services/voice_dialog.dart';

void main() {
  group('parseYesNo Tests - Numbers 1 (Yes) and 2 (No)', () {
    test('recognizes standard 1 as Yes and 2 as No', () {
      expect(parseYesNo('1'), true);
      expect(parseYesNo('2'), false);
      expect(parseYesNo('un'), true);
      expect(parseYesNo('deux'), false);
      expect(parseYesNo('oui'), true);
      expect(parseYesNo('non'), false);
    });

    test('recognizes 1 and 2 even when preceded or followed by Vosk [unk] noise', () {
      expect(parseYesNo('[unk] 1'), true);
      expect(parseYesNo('1 [unk]'), true);
      expect(parseYesNo('[unk] un'), true);
      expect(parseYesNo('un [unk]'), true);

      expect(parseYesNo('[unk] 2'), false);
      expect(parseYesNo('2 [unk]'), false);
      expect(parseYesNo('[unk] deux'), false);
      expect(parseYesNo('deux [unk]'), false);
    });

    test('recognizes phrases with choices and ordinals', () {
      expect(parseYesNo('choix 1'), true);
      expect(parseYesNo('option 1'), true);
      expect(parseYesNo('premier'), true);
      expect(parseYesNo('le 1'), true);

      expect(parseYesNo('choix 2'), false);
      expect(parseYesNo('option 2'), false);
      expect(parseYesNo('second'), false);
      expect(parseYesNo('le 2'), false);
    });

    test('returns null for ambiguous phrases or pure unk noise', () {
      expect(parseYesNo('[unk]'), null);
      expect(parseYesNo(''), null);
      expect(parseYesNo('1 et 2'), null);
    });
  });
}
