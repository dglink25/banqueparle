import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../utils/onboarding_storage.dart';
import 'voice_dialog.dart';

/// Ecoute la reponse de l'utilisateur et renvoie le texte reconnu, ou null
/// si rien n'a ete entendu apres [timeout] (10 secondes par defaut, comme
/// demande : sans reponse, l'appelant relance la question).
///
/// Utilisee a la fois par le service d'arriere-plan (headless) et par
/// l'interface au premier plan.
///
/// Points de robustesse (corriges apres des echecs repetes sur les mots
/// courts : "un", "deux", "solde") :
///
///  - On conserve le MEILLEUR texte non vide recu. Avant, chaque resultat
///    ecrasait le precedent, y compris un resultat final vide, ce qui
///    pouvait effacer un "un" pourtant capte en resultat partiel.
///  - Plusieurs tentatives d'ecoute dans la fenetre de [timeout] : si le
///    moteur Android s'arrete de lui-meme sans resultat (debut de parole
///    coupe, "no match"), on relance l'ecoute au lieu d'abandonner.
///  - Les reponses courtes (oui/non, choix de menu) utilisent le mode
///    "confirmation" du moteur, prevu pour ce cas, plutot que la dictee
///    libre qui ecarte souvent les mots isoles a faible confiance.
///  - On attend que le statut "ecoute" soit etabli avant de surveiller sa
///    fin : sinon la fonction pouvait conclure "rien entendu" avant meme
///    le demarrage reel de la reconnaissance.
///
/// [shouldStop] permet d'interrompre immediatement l'ecoute (appui sur une
/// touche du pave numerique).
Future<String?> sttListenOnce(
  stt.SpeechToText speech, {
  Duration timeout = const Duration(seconds: 10),
  Duration? pauseFor,
  bool? shortAnswer,
  bool Function()? shouldStop,
}) async {
  final short = shortAnswer ?? ListenHint.shortAnswer;
  final pause = pauseFor ??
      (short ? const Duration(seconds: 2) : const Duration(seconds: 4));

  // Court delai apres la synthese vocale : evite de capter sa toute fin
  // (relachement tardif du focus audio) sans retarder la reponse de
  // l'utilisateur, qui parle souvent des la fin de la question.
  await Future.delayed(const Duration(milliseconds: 150));

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
          if (words.isNotEmpty) heardNow = words; // jamais ecraser par du vide
        },
        listenFor: remaining < const Duration(seconds: 4)
            ? const Duration(seconds: 4)
            : remaining,
        pauseFor: pause,
        partialResults: true,
        localeId: 'fr_FR',
        listenMode:
            short ? stt.ListenMode.confirmation : stt.ListenMode.dictation,
      );
    } catch (_) {
      started = false;
    }

    if (!started) {
      await Future.delayed(const Duration(milliseconds: 400));
      continue;
    }

    // Laisse le statut "ecoute" s'etablir avant de surveiller sa fin.
    final readyBy = DateTime.now().add(const Duration(milliseconds: 1500));
    while (!speech.isListening && DateTime.now().isBefore(readyBy)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Attend la fin naturelle de cette session (silence detecte, ou
    // arret du moteur), avec un filet de securite.
    final hardEnd = DateTime.now().add(timeout + const Duration(seconds: 3));
    while (speech.isListening && DateTime.now().isBefore(hardEnd)) {
      if (shouldStop?.call() ?? false) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (speech.isListening) {
      await speech.stop();
    }
    // Laisse arriver le resultat final, emis juste apres l'arret.
    await Future.delayed(const Duration(milliseconds: 300));

    if (heardNow.isNotEmpty) best = heardNow;
  }

  debugPrint('[STT] entendu : "$best"');
  unawaited(OnboardingStorage.setLastHeard(best.isEmpty ? '(silence)' : best));
  return best.isNotEmpty ? best : null;
}
