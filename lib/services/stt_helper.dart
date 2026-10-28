import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../utils/onboarding_storage.dart';
import 'tts_service.dart';
import 'vosk_engine.dart';
import 'voice_dialog.dart';

/// Ecoute la reponse de l'utilisateur et renvoie le texte reconnu, ou null
/// si rien n'a ete entendu apres [timeout].
Future<String?> sttListenOnce(
  stt.SpeechToText speech, {
  Duration timeout = const Duration(seconds: 10),
  Duration? pauseFor,
  bool? shortAnswer,
  bool Function()? shouldStop,
}) async {
  // S'assure que le haut-parleur TTS est totalement coupé
  try {
    await TtsService.instance.stop();
  } catch (_) {}

  // 1. Si un vocabulaire restreint est défini, tentative avec Vosk (hors ligne).
  final grammar = ListenHint.grammar;
  if (grammar != null) {
    try {
      final outcome = await VoiceRouter.listenConstrained(
        grammar: grammar,
        timeout: const Duration(seconds: 4), // court délai pour ne pas bloquer l'utilisateur
        shouldStop: shouldStop,
      );
      if (!outcome.unavailable) {
        final heard = outcome.text;
        // Si un vrai mot du vocabulaire a été entendu (hors [unk])
        if (heard != null && heard.isNotEmpty && !heard.contains('[unk]')) {
          debugPrint('[Vosk] entendu : "$heard"');
          unawaited(OnboardingStorage.setLastHeard('[hors ligne] $heard'));
          return heard;
        }
      }
    } catch (_) {}
    // Si Vosk a renvoyé du silence ou [unk], on enchaîne immédiatement
    // avec le moteur Google STT ci-dessous sans échouer.
  }

  final short = shortAnswer ?? ListenHint.shortAnswer;
  final pause = pauseFor ??
      (short ? const Duration(seconds: 2) : const Duration(seconds: 4));

  // Délai de protection acoustique anti-écho du haut-parleur
  await Future.delayed(const Duration(milliseconds: 300));

  final overall = DateTime.now().add(timeout);
  String best = '';

  while (best.isEmpty && DateTime.now().isBefore(overall)) {
    if (shouldStop?.call() ?? false) break;

    String heardNow = '';
    var started = true;
    try {
      final remaining = overall.difference(DateTime.now());
      await speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) heardNow = words;
          if (short && result.finalResult && words.isNotEmpty) {
            unawaited(speech.stop());
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          listenFor: remaining < const Duration(seconds: 4)
              ? const Duration(seconds: 4)
              : remaining,
          pauseFor: pause,
          localeId: 'fr_FR',
        ),
      );
    } catch (_) {
      started = false;
    }

    if (!started) {
      await Future.delayed(const Duration(milliseconds: 300));
      continue;
    }

    // Laisse le statut "ecoute" s'etablir avant de surveiller sa fin
    final readyBy = DateTime.now().add(const Duration(milliseconds: 1200));
    while (!speech.isListening && DateTime.now().isBefore(readyBy)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Attend la fin naturelle de l'écoute
    final hardEnd = DateTime.now().add(timeout + const Duration(seconds: 2));
    while (speech.isListening && DateTime.now().isBefore(hardEnd)) {
      if (shouldStop?.call() ?? false) break;
      await Future.delayed(const Duration(milliseconds: 80));
    }

    if (speech.isListening) {
      try {
        await speech.stop();
      } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 200));
    if (heardNow.isNotEmpty) best = heardNow;
  }

  debugPrint('[STT] entendu : "$best"');
  unawaited(OnboardingStorage.setLastHeard(best.isEmpty ? '(silence)' : best));
  return best.isNotEmpty ? best : null;
}
