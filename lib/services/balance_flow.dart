import '../utils/amount_parser.dart';
import 'auth_gate.dart';
import 'transfer_service.dart';
import 'voice_dialog.dart';

/// Touche 1 - Consulter le solde. Securite : biometrie.
/// Lecture avec la precision des centimes lorsqu'il y en a.
class BalanceFlow {
  final SpeakFn speak;
  final ListenFn listen;

  BalanceFlow({required this.speak, required this.listen});

  Future<void> run() async {
    final gate = AuthGate(speak: speak, listen: listen);
    if (!await gate.biometric('Consulter votre solde')) {
      await speak('Identité non confirmée. Le solde n\'est pas communiqué.');
      return;
    }

    final balance = await TransferService.getBalance();
    if (balance == null) {
      await speak(
        'Impossible de lire votre solde. Vérifiez votre connexion '
        'internet, puis réessayez.',
      );
      return;
    }
    await speak('Votre solde est de ${speakAmount(balance)}.');
  }
}
