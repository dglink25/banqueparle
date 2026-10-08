import 'auth_gate.dart';
import 'transfer_service.dart';
import 'voice_dialog.dart';

/// Touche 4 - Code OTP de securite. Securite : biometrie.
/// Le code est genere par la base de donnees (generateur cryptographique,
/// valable 5 minutes, a usage unique) puis dicte chiffre par chiffre.
class OtpFlow {
  final SpeakFn speak;
  final ListenFn listen;

  OtpFlow({required this.speak, required this.listen});

  static const int kMaxRepeats = 3;

  Future<void> run() async {
    final gate = AuthGate(speak: speak, listen: listen);
    if (!await gate.biometric('Generer un code de securite')) {
      await speak('Identite non confirmee. Aucun code n\'est genere.');
      return;
    }

    final result = await TransferService.generateOtp();
    if (result.code == null) {
      await speak(result.error ?? 'Impossible de generer le code.');
      return;
    }

    final spelled = result.code!.split('').join(' ');
    await speak(
      'Votre code a usage unique est : $spelled. Il est valable cinq '
      'minutes.',
    );

    for (var i = 0; i < kMaxRepeats; i++) {
      final answer = await askWithRetry(
        speak: speak,
        listen: listen,
        question: 'Dites 1 pour repeter le code, ou 2 pour terminer.',
        maxRetries: 1,
      );
      if (answer == null || parseYesNo(answer) != true) return;
      await speak('Je repete : $spelled.');
    }
  }
}
