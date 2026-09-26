import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Écoute une seule fois et renvoie le texte reconnu, ou null si rien n'a
/// été entendu (silence). Utilisée à la fois par le service d'arrière-plan
/// (headless) et par l'interface au premier plan.
///
/// Important : on n'arrête PAS l'écoute dès le premier "finalResult". Sur
/// certains appareils, le moteur de reconnaissance Android marque un
/// résultat comme final après seulement un mot ou une syllabe, ce qui
/// tronquait les réponses (ex: un nom complet coupé après le prénom). On
/// laisse maintenant le moteur terminer naturellement (silence prolongé
/// détecté via [pauseFor], ou durée maximale [timeout] atteinte), puis on
/// renvoie le dernier texte cumulé reçu.
Future<String?> sttListenOnce(
  stt.SpeechToText speech, {
  Duration timeout = const Duration(seconds: 12),
  Duration pauseFor = const Duration(seconds: 5),
}) async {
  // Petite pause avant de démarrer l'écoute : évite de capter la fin de
  // la synthèse vocale de la question qui vient d'être posée (écho /
  // relâchement tardif du focus audio par le moteur TTS).
  await Future.delayed(const Duration(milliseconds: 400));

  String lastWords = '';

  try {
    await speech.listen(
      onResult: (result) {
        lastWords = result.recognizedWords;
      },
      listenFor: timeout,
      pauseFor: pauseFor,
      partialResults: true,
      localeId: 'fr_FR',
      listenMode: stt.ListenMode.dictation,
    );
  } catch (e) {
    return null;
  }

  // Attend que le moteur de reconnaissance s'arrête de lui-même (silence
  // détecté ou durée maximale atteinte), avec un filet de sécurité pour
  // ne jamais bloquer indéfiniment.
  final deadline = DateTime.now().add(timeout + const Duration(seconds: 3));
  while (speech.isListening && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  if (speech.isListening) {
    await speech.stop();
  }

  return lastWords.trim().isNotEmpty ? lastWords.trim() : null;
}
