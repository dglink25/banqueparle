import '../utils/native_channel.dart';
import 'voice_dialog.dart';

/// Touche 6 - Contacter un conseiller. Securite : aucune.
/// Met en relation telephonique directe avec le centre de relation
/// client. Le numero est fourni a la compilation (ADVISOR_PHONE), il
/// n'est donc pas code en dur dans le depot.
class AdvisorFlow {
  final SpeakFn speak;

  AdvisorFlow({required this.speak});

  static const String phone = String.fromEnvironment('ADVISOR_PHONE');

  Future<void> run() async {
    if (phone.trim().isEmpty) {
      await speak(
        'Le numero du centre de relation client n\'est pas configure dans '
        'cette version de l\'application.',
      );
      return;
    }
    await speak('Mise en relation avec un conseiller. Appel en cours.');
    try {
      await kNativeChannel.invokeMethod('callPhone', {'number': phone});
    } catch (_) {
      await speak('Impossible de lancer l\'appel sur ce telephone.');
    }
  }
}
