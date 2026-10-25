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
    if (!await gate.biometric('Générer un code de sécurité')) {
      await speak('Identité non confirmée. Aucun code n\'est généré.');
      return;
    }

    final result = await TransferService.generateOtp();
    if (result.code == null) {
      await speak(result.error ?? 'Impossible de générer le code.');
      return;
    }

    final spelled = result.code!.split('').join(' ');
    await speak(
      'Votre code à usage unique est : $spelled. Il est valable cinq '
      'minutes.',
    );

    for (var i = 0; i < kMaxRepeats; i++) {
      final repeat = await askYesNo(
        speak: speak,
        listen: listen,
        question: 'Souhaitez-vous que je répète le code ?',
        hint: 'Dites 1 pour répéter, ou 2 pour terminer.',
        simpleHint: 'Dites simplement oui pour répéter, ou non pour terminer.',
        maxAttempts: 2,
      );
      if (repeat != true) return;
      await speak('Je répète : $spelled.');
    }
  }
}
