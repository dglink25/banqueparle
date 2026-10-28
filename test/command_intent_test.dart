import 'package:flutter_test/flutter_test.dart';
import 'package:banqueparle/services/command_intent.dart';

void main() {
  group('CommandIntent Tests', () {
    test('recognizes solde and soldes', () {
      expect(detectIntent('solde'), BankIntent.balance);
      expect(detectIntent('soldes'), BankIntent.balance);
      expect(detectIntent('mon solde'), BankIntent.balance);
      expect(detectIntent('combien j ai sur mon compte'), BankIntent.balance);
      expect(detectIntent('avoir'), BankIntent.balance);
    });

    test('recognizes numbers and ordinals mapped to intents', () {
      // 1 -> balance
      expect(detectIntent('1'), BankIntent.balance);
      expect(detectIntent('un'), BankIntent.balance);
      expect(detectIntent('premier'), BankIntent.balance);

      // 2 -> history
      expect(detectIntent('2'), BankIntent.history);
      expect(detectIntent('deux'), BankIntent.history);
      expect(detectIntent('second'), BankIntent.history);

      // 3 -> transfer
      expect(detectIntent('3'), BankIntent.transfer);
      expect(detectIntent('trois'), BankIntent.transfer);

      // 4 -> otp
      expect(detectIntent('4'), BankIntent.otp);
      expect(detectIntent('quatre'), BankIntent.otp);

      // 5 -> profile
      expect(detectIntent('5'), BankIntent.profile);
      expect(detectIntent('cinq'), BankIntent.profile);

      // 0 -> quit
      expect(detectIntent('0'), BankIntent.quit);
      expect(detectIntent('quitter'), BankIntent.quit);
      expect(detectIntent('arreter'), BankIntent.quit);
    });

    test('prioritizes first spoken intent in complex utterances', () {
      expect(detectIntent('consulter solde et virement'), BankIntent.balance);
      expect(detectIntent('faire un virement après le solde'), BankIntent.transfer);
    });

    test('returns none for unrecognized phrases', () {
      expect(detectIntent('bonjour comment ca va'), BankIntent.none);
    });
  });
}
