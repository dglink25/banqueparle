import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';

import '../utils/onboarding_storage.dart';

/// -----------------------------------------------------------------------
/// Reconnaissance vocale hors ligne (Vosk) a vocabulaire restreint.
///
/// Pourquoi : le moteur generaliste de Google ecarte souvent les mots isoles
/// ("un", "deux", "solde") et comprend mal l'accent beninois, surtout sans
/// bonne connexion. Quand les reponses possibles sont connues, Vosk n'ecoute
/// que ces mots : il choisit parmi quelques candidats au lieu de deviner
/// n'importe quelle phrase, ce qui le rend tres tolerant a l'accent. Il
/// fonctionne sans internet.
///
/// Architecture : un SEUL modele est charge, dans le service d'arriere-plan
/// (qui possede donc le micro). L'ecran lui delegue ses ecoutes par messages
/// ([VoskRemote]). Cela evite de charger le modele deux fois (memoire) et
/// toute concurrence sur le micro.
///
/// Repli : si Vosk n'est pas disponible (modele pas encore extrait, erreur),
/// toutes les fonctions renvoient "indisponible" et l'appelant utilise le
/// moteur Google comme avant. Rien ne regresse.
///
/// Piege connu de Vosk en mode grammaire : il reconnait parfois les mots sans
/// jamais emettre de resultat FINAL, seulement des resultats partiels. On
/// valide donc un resultat partiel qui reste stable.
/// -----------------------------------------------------------------------

class VoskOutcome {
  /// Texte entendu, null si silence. "[unk]" si de la parole a ete entendue
  /// mais n'appartient pas au vocabulaire demande.
  final String? text;

  /// Vrai si le moteur n'est pas utilisable : l'appelant doit se replier.
  final bool unavailable;

  const VoskOutcome.heard(this.text) : unavailable = false;
  const VoskOutcome.unavailable()
      : text = null,
        unavailable = true;
}

class VoskEngine {
  VoskEngine._();

  static const String modelAsset =
      'assets/models/vosk-model-small-fr-0.22.zip';
  static const int _sampleRate = 16000;

  /// Vrai uniquement dans l'isolat du service d'arriere-plan.
  static bool isOwner = false;

  static VoskFlutterPlugin? _vosk;
  static Model? _model;
  static Recognizer? _recognizer;
  static SpeechService? _service;
  static StreamSubscription<String>? _subResult;
  static StreamSubscription<String>? _subPartial;
  static Timer? _stableTimer;
  static bool _wakeOn = false;
  static DateTime _lastLoadAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _tail = Future.value();

  // ---------------------------------------------------------------------
  // Cote ecran : extraction du modele depuis les assets (une seule fois)
  // ---------------------------------------------------------------------

  /// Extrait le modele dans le stockage de l'application et memorise son
  /// chemin. Appele par l'ecran au demarrage, sans bloquer l'interface :
  /// la premiere extraction prend quelques dizaines de secondes.
  static Future<void> prepareModelFromAssets() async {
    try {
      final known = await OnboardingStorage.getVoskModelPath();
      if (known != null && Directory(known).existsSync()) return;
      await OnboardingStorage.setVoiceStatus(
        'Préparation du modèle vocal (première ouverture)...',
      );
      final path = await ModelLoader().loadFromAssets(modelAsset);
      await OnboardingStorage.setVoskModelPath(path);
      await OnboardingStorage.setVoiceStatus('Modèle vocal prêt.');
    } catch (e) {
      await OnboardingStorage.setVoiceStatus(
        'Modèle vocal indisponible : ${_short(e)}',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Cote service : chargement du modele
  // ---------------------------------------------------------------------

  static bool get isReady => _model != null;
  static bool get wakeRunning => _wakeOn;

  /// Charge le modele s'il est disponible. Peu couteux quand il est deja
  /// charge ; limite a une tentative toutes les 8 secondes sinon.
  static Future<bool> ensureReady() async {
    if (_model != null) return true;
    if (DateTime.now().difference(_lastLoadAttempt) <
        const Duration(seconds: 8)) {
      return false;
    }
    _lastLoadAttempt = DateTime.now();
    try {
      final path = await OnboardingStorage.getVoskModelPath();
      if (path == null || !Directory(path).existsSync()) {
        await OnboardingStorage.setVoiceStatus(
          'En attente du modèle vocal : ouvrez l\'application une fois. '
          'Moteur de repli : Google.',
        );
        return false;
      }
      _vosk ??= VoskFlutterPlugin.instance();
      _model = await _vosk!.createModel(path);
      await OnboardingStorage.setVoiceStatus(
        'Moteur vocal : Vosk hors ligne actif.',
      );
      return true;
    } catch (e) {
      await OnboardingStorage.setVoiceStatus(
        'Vosk indisponible (${_short(e)}). Moteur de repli : Google.',
      );
      return false;
    }
  }

  // ---------------------------------------------------------------------
  // Exclusion mutuelle : une seule operation sur le micro a la fois
  // ---------------------------------------------------------------------

  static Future<T> _exclusive<T>(Future<T> Function() body) async {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    try {
      await previous;
      return await body();
    } finally {
      gate.complete();
    }
  }

  // ---------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 90 ? '${s.substring(0, 90)}...' : s;
  }

  /// Retire les marqueurs "[unk]" et normalise les espaces.
  static String _clean(String raw) =>
      raw.replaceAll('[unk]', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _extract(String json, String key) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map && decoded[key] != null) {
        return decoded[key].toString();
      }
    } catch (_) {}
    return '';
  }

  // ---------------------------------------------------------------------
  // Demarrage / arret du flux micro
  // ---------------------------------------------------------------------

  static Future<void> _begin(
    List<String> grammar,
    void Function(String raw) onFinal,
    void Function(String raw) onPartial,
  ) async {
    final vosk = _vosk!;
    final recognizer = await vosk.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
      grammar: grammar,
    );
    final service = await vosk.initSpeechService(recognizer);
    _recognizer = recognizer;
    _service = service;
    _subResult =
        service.onResult().listen((j) => onFinal(_extract(j, 'text')));
    _subPartial =
        service.onPartial().listen((j) => onPartial(_extract(j, 'partial')));
    await service.start();
  }

  static Future<void> _end() async {
    _stableTimer?.cancel();
    _stableTimer = null;
    try {
      await _subResult?.cancel();
      await _subPartial?.cancel();
    } catch (_) {}
    _subResult = null;
    _subPartial = null;

    final service = _service;
    _service = null;
    if (service != null) {
      try {
        await service.stop();
      } catch (_) {}
      try {
        await service.dispose();
      } catch (_) {}
    }
    final recognizer = _recognizer;
    _recognizer = null;
    if (recognizer != null) {
      try {
        // Appel dynamique : liberation du reconnaisseur si la methode
        // existe dans cette version du plugin.
        await (recognizer as dynamic).dispose();
      } catch (_) {}
    }
  }

  static Future<void> _endWake() async {
    if (_wakeOn) {
      _wakeOn = false;
      await _end();
    }
  }

  // ---------------------------------------------------------------------
  // Ecoute d'une reponse (une fois)
  // ---------------------------------------------------------------------

  /// Ecoute une reponse limitee a [grammar]. Renvoie le texte entendu,
  /// "[unk]" si de la parole hors vocabulaire a ete entendue, null si
  /// silence, ou "indisponible" pour que l'appelant se replie sur Google.
  ///
  /// Les sons hors vocabulaire n'interrompent pas l'ecoute : l'utilisateur
  /// peut se reprendre dans la meme fenetre de [timeout], ce qui laisse
  /// naturellement une seconde chance.
  static Future<VoskOutcome> listenOnce({
    required List<String> grammar,
    Duration timeout = const Duration(seconds: 10),
    bool Function()? shouldStop,
  }) =>
      _exclusive(() async {
        if (!await ensureReady()) return const VoskOutcome.unavailable();
        await _endWake();

        // Court delai : evite de capter la toute fin de la synthese vocale
        // (la question se termine souvent par "...ou 2 pour non").
        await Future.delayed(const Duration(milliseconds: 350));

        String? good;
        var sawUnknown = false;
        var partial = '';
        var partialChangedAt = DateTime.now();
        final done = Completer<void>();

        void onFinal(String raw) {
          final cleaned = _clean(raw);
          if (cleaned.isEmpty) {
            if (raw.contains('[unk]')) sawUnknown = true;
            return;
          }
          good = cleaned;
          if (!done.isCompleted) done.complete();
        }

        void onPartial(String raw) {
          final cleaned = _clean(raw);
          if (cleaned != partial) {
            partial = cleaned;
            partialChangedAt = DateTime.now();
          }
        }

        try {
          await _begin(grammar, onFinal, onPartial);
        } catch (e) {
          await OnboardingStorage.setVoiceStatus(
            'Vosk : échec du micro (${_short(e)}). Moteur de repli : Google.',
          );
          await _end();
          return const VoskOutcome.unavailable();
        }

        final deadline = DateTime.now().add(timeout);
        while (!done.isCompleted && DateTime.now().isBefore(deadline)) {
          if (shouldStop?.call() ?? false) break;
          // Resultat partiel stable : accepte comme final (voir l'en-tete).
          if (partial.isNotEmpty &&
              DateTime.now().difference(partialChangedAt) >=
                  const Duration(milliseconds: 800)) {
            good = partial;
            break;
          }
          await Future.any([
            done.future,
            Future.delayed(const Duration(milliseconds: 80)),
          ]);
        }

        await _end();
        if (good != null) return VoskOutcome.heard(good);
        return VoskOutcome.heard(sawUnknown ? '[unk]' : null);
      });

  // ---------------------------------------------------------------------
  // Ecoute continue du mot-cle
  // ---------------------------------------------------------------------

  /// Demarre l'ecoute continue du mot-cle. [onText] recoit une phrase
  /// complete ("banque parlante solde"), des qu'un resultat final arrive
  /// ou que le resultat partiel reste stable pendant 0,9 seconde.
  static Future<bool> startWake({
    required List<String> grammar,
    required void Function(String text) onText,
  }) =>
      _exclusive(() async {
        if (_wakeOn) return true;
        if (!await ensureReady()) return false;
        try {
          void fire(String cleaned) {
            _stableTimer?.cancel();
            if (cleaned.isNotEmpty) onText(cleaned);
          }

          await _begin(
            grammar,
            (raw) => fire(_clean(raw)),
            (raw) {
              final cleaned = _clean(raw);
              _stableTimer?.cancel();
              if (cleaned.isEmpty) return;
              _stableTimer = Timer(
                const Duration(milliseconds: 900),
                () => fire(cleaned),
              );
            },
          );
          _wakeOn = true;
          return true;
        } catch (e) {
          await OnboardingStorage.setVoiceStatus(
            'Vosk : écoute du mot-clé impossible (${_short(e)}). '
            'Moteur de repli : Google.',
          );
          await _end();
          return false;
        }
      });

  static Future<void> stopWake() => _exclusive(_endWake);
}

/// Cote ecran : delegue une ecoute au service d'arriere-plan, qui possede
/// le modele et le micro.
class VoskRemote {
  VoskRemote._();

  static DateTime _downUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<VoskOutcome> listen({
    required List<String> grammar,
    required Duration timeout,
    bool Function()? shouldStop,
  }) async {
    // Si le service n'a pas repondu recemment, ne pas retarder chaque
    // question : repli immediat sur Google pendant quelques secondes.
    if (DateTime.now().isBefore(_downUntil)) {
      return const VoskOutcome.unavailable();
    }

    final service = FlutterBackgroundService();
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final reply = Completer<Map<String, dynamic>?>();

    final sub = service.on('vosk_heard').listen((event) {
      if (event != null &&
          event['id']?.toString() == id &&
          !reply.isCompleted) {
        reply.complete(event);
      }
    });

    Timer? watcher;
    try {
      service.invoke('vosk_listen', {
        'id': id,
        'grammar': grammar,
        'timeoutMs': timeout.inMilliseconds,
      });

      watcher = Timer.periodic(const Duration(milliseconds: 150), (t) {
        if (shouldStop?.call() ?? false) {
          service.invoke('vosk_cancel', {'id': id});
          t.cancel();
        }
      });

      final answer = await reply.future.timeout(
        timeout + const Duration(seconds: 6),
        onTimeout: () => null,
      );

      if (answer == null) {
        _downUntil = DateTime.now().add(const Duration(seconds: 30));
        return const VoskOutcome.unavailable();
      }
      if (answer['unavailable'] == true) {
        _downUntil = DateTime.now().add(const Duration(seconds: 20));
        return const VoskOutcome.unavailable();
      }
      return VoskOutcome.heard(answer['text'] as String?);
    } finally {
      watcher?.cancel();
      await sub.cancel();
    }
  }
}

/// Point d'entree unique : dans le service, utilise le moteur directement ;
/// dans l'ecran, delegue au service.
class VoiceRouter {
  VoiceRouter._();

  static Future<VoskOutcome> listenConstrained({
    required List<String> grammar,
    required Duration timeout,
    bool Function()? shouldStop,
  }) {
    if (VoskEngine.isOwner) {
      return VoskEngine.listenOnce(
        grammar: grammar,
        timeout: timeout,
        shouldStop: shouldStop,
      );
    }
    return VoskRemote.listen(
      grammar: grammar,
      timeout: timeout,
      shouldStop: shouldStop,
    );
  }
}
