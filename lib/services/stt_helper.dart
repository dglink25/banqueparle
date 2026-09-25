import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Écoute une seule fois pendant ~[timeout] et renvoie le texte reconnu,
/// ou null si rien n'a été entendu (silence). Utilisée à la fois par le
/// service d'arrière-plan (headless) et par l'interface au premier plan.
Future<String?> sttListenOnce(
  stt.SpeechToText speech, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<String?>();
  String lastWords = '';

  try {
    await speech.listen(
      onResult: (result) {
        lastWords = result.recognizedWords;
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(lastWords);
        }
      },
      listenFor: timeout,
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: 'fr_FR',
      listenMode: stt.ListenMode.dictation,
    );
  } catch (e) {
    if (!completer.isCompleted) completer.complete(null);
  }

  unawaited(Future.delayed(timeout + const Duration(seconds: 2), () {
    if (!completer.isCompleted) {
      completer.complete(lastWords.isNotEmpty ? lastWords : null);
    }
  }));

  final result = await completer.future;
  await speech.stop();
  return result;
}
