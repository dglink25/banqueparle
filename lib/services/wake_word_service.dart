import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../utils/onboarding_storage.dart';
import '../utils/permissions_helper.dart';
import '../utils/text_normalize.dart';
import 'command_intent.dart';
import 'grammars.dart';
import 'onboarding_fields.dart';
import 'stop_command.dart';
import 'sync_service.dart';
import 'local_cache.dart';
import 'stt_helper.dart';
import 'voice_dialog.dart';
import 'vosk_engine.dart';
import 'vosk_guard.dart';

/// -----------------------------------------------------------------------
/// WakeWordService
///
/// Tourne en Foreground Service Android (notification persistante) et
/// écoute en continu le microphone via speech_to_text.
///
/// Dès que « Banque Parlante » est détecté :
///   1. Le service PARLE LUI-MÊME (TTS embarqué dans cet isolat headless),
///      ce qui garantit une réponse vocale même si Android refuse
///      d'ouvrir l'interface (restriction "Full-Screen Intent" d'Android
///      14+, voir README) ou si l'application a été totalement fermée.
///   2. S'il s'agit du tout premier usage, il mène l'enrôlement vocal
///      complet (identité, compte bancaire) intégralement en arrière-plan,
///      sans dépendre de l'interface. Champs déjà répondus lors d'une
///      tentative précédente : ignorés (reprise naturelle).
///   3. Il tente en complément d'amener l'application au premier plan
///      (notification plein écran) pour l'étape empreinte digitale, qui
///      nécessite obligatoirement l'interface (contrainte Android :
///      la biométrie ne peut être invoquée que depuis un écran affiché).
/// -----------------------------------------------------------------------

const String kNotifChannelId = 'banqueparle_wakeword_channel';
const String kNotifChannelName = 'BanqueParle - Écoute active';
const int kForegroundNotifId = 888;
const int kWakeNotifId = 999;

/// Variantes phonétiques / homophones tolérées pour le mot-clé.
const List<String> kWakeVariants = [
  'banque parlante',
  'banc parlant',
  'banque parlant',
  'banc parlante',
  'banque parle',
  'ma banque parlante',
];

bool containsWakeWord(String recognized) {
  final norm = normalizeText(recognized);
  for (final variant in kWakeVariants) {
    if (norm.contains(normalizeText(variant))) return true;
  }
  return false;
}

Future<bool> _fieldsAllPresent(List<OnboardingField> fields) async {
  for (final f in fields) {
    final v = await OnboardingStorage.getField(f.key);
    if (v == null || v.isEmpty) return false;
  }
  return true;
}

/// Initialise le service d'arrière-plan sans le démarrer avant d'avoir les permissions.
Future<void> initializeWakeWordService() async {
  try {
    final service = FlutterBackgroundService();

    final flnp = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await flnp.initialize(const InitializationSettings(android: androidInit));

    const serviceChannel = AndroidNotificationChannel(
      kNotifChannelId,
      kNotifChannelName,
      description: 'Indique que BanqueParle écoute le mot-clé en arrière-plan.',
      importance: Importance.low,
    );

    const wakeChannel = AndroidNotificationChannel(
      'banqueparle_wake_channel',
      'BanqueParle - Réveil',
      description: 'Réveille l\'application quand le mot-clé est détecté.',
      importance: Importance.max,
    );

    await flnp
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(serviceChannel);
    await flnp
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(wakeChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: kNotifChannelId,
        initialNotificationTitle: 'BanqueParle',
        initialNotificationContent: 'Écoute du mot-clé « Banque Parlante »…',
        foregroundServiceNotificationId: kForegroundNotifId,
        foregroundServiceTypes: [AndroidForegroundType.microphone],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onServiceStart,
        onBackground: (service) async => true,
      ),
    );
  } catch (e) {
    debugPrint('[WakeWordService] Erreur initialisation service: $e');
  }
}

/// Démarre le service d'arrière-plan si et seulement si la permission micro est accordée.
/// Sur Android 14+, démarrer un service de type microphone sans permission accordée
/// lève un crash fatal SecurityException immédiat.
Future<void> startWakeWordServiceIfPermitted() async {
  try {
    final hasMic = await PermissionsHelper.hasMicrophonePermission();
    if (!hasMic) {
      debugPrint('[WakeWord] Permission micro non encore accordée : démarrage différé.');
      return;
    }

    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
      debugPrint('[WakeWord] Service d\'arrière-plan démarré avec succès.');
    }
  } catch (e) {
    debugPrint('[WakeWord] Erreur lors du démarrage du service: $e');
  }
}

/// Point d'entrée exécuté dans l'isolate du service d'arrière-plan.
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final stt.SpeechToText speech = stt.SpeechToText();
  final FlutterLocalNotificationsPlugin flnp =
      FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flnp.initialize(const InitializationSettings(android: androidInit));

  // TTS propre à cet isolat headless : c'est LUI qui garantit la réponse
  // vocale même si l'interface ne s'ouvre pas.
  final FlutterTts tts = FlutterTts();
  await tts.setLanguage('fr-FR');
  await tts.setSpeechRate(0.5);
  await tts.setPitch(1.0);
  await tts.setVolume(1.0);
  Future<void> speak(String text) async {
    await tts.stop();
    // Les gestionnaires de fin sont poses AVANT de lancer la synthese :
    // sinon une fin de lecture rapide pouvait etre manquee, et l'ecoute
    // demarrait alors en pleine parole de l'application.
    final completer = Completer<void>();
    void done() {
      if (!completer.isCompleted) completer.complete();
    }

    tts.setCompletionHandler(done);
    tts.setCancelHandler(done);
    tts.setErrorHandler((_) => done());
    await tts.speak(text);
    await completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {},
    );
  }

  bool speechReady = await speech.initialize(
    onError: (e) => debugPrint('[WakeWord] Erreur STT: $e'),
    onStatus: (status) => debugPrint('[WakeWord] Statut STT: $status'),
  );

  if (service is AndroidServiceInstance) {
    try {
      await service.setAsForegroundService();
    } catch (e) {
      debugPrint('[WakeWord] Erreur setAsForegroundService: $e');
    }
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    speech.stop();
    unawaited(VoskEngine.stopWake());
    service.stopSelf();
  });

  // --- Moteur hors ligne Vosk : le service en est l'unique proprietaire ---
  // (un seul modele en memoire, un seul acces au micro). L'ecran lui
  // delegue ses ecoutes par messages.
  VoskEngine.isOwner = true;
  await VoskGuard.inspect();
  // Par défaut en pause au démarrage : laisse l'écran actif au premier plan
  // interagir avec l'utilisateur sans conflit matériel sur le microphone.
  bool pausedByForeground = true;
  service.on('pause_wake').listen((event) async {
    pausedByForeground = true;
    try {
      if (speech.isListening) await speech.stop();
      if (VoskEngine.wakeRunning) await VoskEngine.stopWake();
    } catch (_) {}
  });

  service.on('resume_wake').listen((event) async {
    pausedByForeground = false;
  });

  final cancelledRemote = <String>{};
  service.on('vosk_cancel').listen((event) {
    final id = event?['id']?.toString();
    if (id != null) cancelledRemote.add(id);
  });
  service.on('vosk_listen').listen((event) async {
    if (event == null) return;
    final id = event['id']?.toString() ?? '';
    final grammar = (event['grammar'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final timeoutMs = (event['timeoutMs'] as num?)?.toInt() ?? 10000;

    VoskOutcome outcome;
    try {
      outcome = await VoskEngine.listenOnce(
        grammar: grammar,
        timeout: Duration(milliseconds: timeoutMs),
        shouldStop: () => cancelledRemote.contains(id),
      );
    } catch (_) {
      outcome = const VoskOutcome.unavailable();
    }
    cancelledRemote.remove(id);
    service.invoke('vosk_heard', {
      'id': id,
      'text': outcome.text,
      'unavailable': outcome.unavailable,
    });
  });

  if (!speechReady) {
    // Le moteur Google est absent ou refuse : ce n'est plus une raison
    // d'arreter le service, Vosk peut assurer l'ecoute du mot-cle.
    debugPrint('[WakeWord] speech_to_text indisponible sur cet appareil.');
  }

  bool handlingWakeWord = false; // evite les declenchements concurrents

  // Capture de la phrase complete apres le mot-cle ("Banque Parlante
  // solde"). Des que le mot-cle apparait, on laisse un court delai
  // d'ecoute supplementaire pour recevoir la suite de la phrase, au lieu
  // de couper aussitot comme avant (la demande dite dans la meme phrase
  // etait perdue).
  Timer? graceTimer;
  String wakeText = '';
  bool wakeArmed = false;

  /// Demande confirmation de l'arret. Sans reponse claire, l'arret est
  /// execute : l'utilisateur l'a demande, et il peut s'agir d'une urgence.
  Future<bool> confirmStop() async {
    final answer = await askYesNo(
      speak: speak,
      listen: () => sttListenOnce(speech),
      question: kStopConfirmQuestion,
      maxAttempts: 3,
    );
    return answer == true;
  }

  Future<void> handleOnce(String utterance) async {
    // "Banque Parlante stop" / "Banque Parlante zero" dit d'emblee.
    if (isStopCommand(utterance)) throw const StopRequested();

    // Toute reponse passe par interceptStop : dire "stop" ou "zero" a
    // n'importe quelle question coupe l'activite au lieu d'etre pris
    // pour un nom, un numero ou une commande.
    final listenFn = interceptStop(() => sttListenOnce(speech));

    final completed = await OnboardingStorage.isCompleted();

    if (!completed) {
      final personalDone = await _fieldsAllPresent(kPersonalInfoFields);
      final bankDone = await _fieldsAllPresent(kBankAccountFields);
      final needsFingerprint = await OnboardingStorage.needsFingerprintStep();
      final needsPin = await OnboardingStorage.needsPinStep();

      if (!personalDone || !bankDone) {
        await speak(
          'Bienvenue sur Banque Parlante. Avant de commencer, '
          'j\'ai besoin de quelques informations pour ouvrir votre '
          'profil.',
        );
        await OnboardingStorage.markBackgroundSpeech();

        final personalOk = personalDone ||
            await runFormFields(
              speak: speak,
              listen: listenFn,
              fields: kPersonalInfoFields,
            );

        final bankOk = personalOk &&
            (bankDone ||
                await runFormFields(
                  speak: speak,
                  listen: listenFn,
                  fields: kBankAccountFields,
                ));

        if (personalOk && bankOk) {
          await OnboardingStorage.setNeedsFingerprintStep(true);
          await OnboardingStorage.setNeedsPinStep(true);
          await speak(
            'Merci. Pour finaliser votre inscription, ouvrez votre '
            'téléphone : nous allons configurer la sécurité de votre '
            'compte, empreinte digitale puis code secret.',
          );
          await OnboardingStorage.markBackgroundSpeech();
          await _triggerAppWakeUp(flnp, service);
        } else {
          await speak(
            'Je n\'ai pas réussi à vous entendre. Redites '
            '"Banque Parlante" quand vous serez prêt à continuer.',
          );
          await OnboardingStorage.markBackgroundSpeech();
        }
      } else if (needsFingerprint || needsPin) {
        await speak(
          'Il reste à finaliser la sécurité de votre compte. '
          'Merci d\'ouvrir votre téléphone.',
        );
        await OnboardingStorage.markBackgroundSpeech();
        await _triggerAppWakeUp(flnp, service);
      }
      return;
    }

    // --- Utilisation normale (enrolement termine) ---
    // La demande peut avoir ete dite dans la meme phrase que le mot-cle
    // ("Banque Parlante solde") : on la traite sans reposer la question.
    final remainder = stripWakeWord(utterance);
    var intent = remainder.isNotEmpty ? detectIntent(remainder) : BankIntent.none;
    String? command;

    if (intent == BankIntent.none) {
      final name = await OnboardingStorage.getField('full_name');
      await speak((name != null && name.isNotEmpty)
          ? 'Bienvenue $name.'
          : 'Bienvenue sur Banque Parlante.');
      await OnboardingStorage.markBackgroundSpeech();

      command = await askWithRetry(
        speak: speak,
        listen: listenFn,
        question: kMenuQuestion,
        retryQuestion: kMenuRetryQuestion,
        maxRetries: 1,
        shortAnswer: true,
        grammar: kMenuGrammar,
        // Vocabulaire restreint (hors ligne) a la premiere tentative ;
        // la relance utilise le moteur Google en secours.
        grammarAttempts: 1,
      );
      if (command != null) intent = detectIntent(command);
    }

    if (intent == BankIntent.quit) {
      // "Quitter" suit la meme confirmation que l'arret d'urgence.
      throw const StopRequested();
    }

    if (intent != BankIntent.none) {
      // Toutes les operations bancaires (reseau, biometrie) s'executent au
      // premier plan : on enregistre l'action, puis on reveille l'ecran.
      await OnboardingStorage.setPendingAction(intent.name);
      await speak('D\'accord : ${intentLabel(intent)}. Ouvrez votre '
          'téléphone si l\'écran ne s\'allume pas.');
      await OnboardingStorage.markBackgroundSpeech();
      await _triggerAppWakeUp(flnp, service);
    } else if (command != null) {
      await speak('Je n\'ai pas compris cette demande. Redites '
          '"Banque Parlante" pour recommencer.');
      await OnboardingStorage.markBackgroundSpeech();
    } else {
      await speak('Je n\'ai pas entendu votre demande. Redites '
          '"Banque Parlante" pour recommencer.');
      await OnboardingStorage.markBackgroundSpeech();
    }
  }

  Future<void> handleWakeWordDetected(String utterance) async {
    if (handlingWakeWord) return;
    handlingWakeWord = true;
    try {
      await speech.stop();
      await VoskEngine.stopWake();

      // Si l'interface traite deja un flux, ne pas parler par-dessus :
      // chevauchement audio et ecoutes concurrentes.
      if (await OnboardingStorage.isFlowInProgress()) {
        debugPrint('[WakeWord] Flux déjà en cours au premier plan, ignore.');
        return;
      }

      var request = utterance;
      while (true) {
        try {
          await handleOnce(request);
          break;
        } on StopRequested {
          if (await confirmStop()) {
            await speak(kStoppedMessage);
            await OnboardingStorage.markBackgroundSpeech();
            // L'application revient en arriere-plan ; le service continue
            // d'ecouter le mot-cle pour la relancer.
            service.invoke('quit_requested');
            break;
          }
          await speak('D\'accord, on reprend.');
          request = '';
        }
      }
    } catch (e) {
      debugPrint('[WakeWord] Erreur pendant le traitement du mot-cle: $e');
    } finally {
      // Laisse s'eteindre la fin de la derniere phrase prononcee avant de
      // reprendre l'ecoute du mot-cle : elle contient souvent "Banque
      // Parlante" ("Redites Banque Parlante...") et se declencherait seule.
      await Future.delayed(const Duration(milliseconds: 1200));
      handlingWakeWord = false;
    }
  }

  void onVoskWakeText(String text) {
    if (handlingWakeWord) return;
    if (!containsWakeWord(text)) {
      final intent = detectIntent(text);
      if (intent == BankIntent.none) return;
    }
    unawaited(handleWakeWordDetected(text));
  }

  void fireWake() {
    graceTimer?.cancel();
    if (!wakeArmed) return;
    wakeArmed = false;
    final heard = wakeText;
    wakeText = '';
    unawaited(() async {
      // Un resultat tardif de la meme session peut arriver pendant que la
      // conversation est deja en cours : ne surtout pas couper l'ecoute
      // de la reponse de l'utilisateur.
      if (handlingWakeWord) return;
      try {
        await speech.stop();
      } catch (_) {}
      await handleWakeWordDetected(heard);
    }());
  }

  final wakeGrammar = buildWakeGrammar();

  Future<void> listenLoop() async {
    while (true) {
      if (pausedByForeground) {
        if (speech.isListening) await speech.stop();
        if (VoskEngine.wakeRunning) await VoskEngine.stopWake();
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      // Le micro ne peut servir qu'a une seule reconnaissance a la fois :
      // pendant qu'un flux vocal tourne au premier plan, le service
      // laisse la main (sinon les deux ecoutes se perturbent). Jamais
      // pendant sa propre conversation : ce serait couper la reponse
      // que l'utilisateur est en train de donner.
      final foregroundBusy = await OnboardingStorage.isFlowInProgress();
      final voskReady = await VoskEngine.ensureReady();

      if (voskReady) {
        // Ecoute du mot-cle hors ligne (Vosk) : prioritaire.
        if (speech.isListening) await speech.stop();
        if (foregroundBusy || handlingWakeWord) {
          if (VoskEngine.wakeRunning && !handlingWakeWord) {
            await VoskEngine.stopWake();
          }
        } else if (!VoskEngine.wakeRunning) {
          final started = await VoskEngine.startWake(
            grammar: wakeGrammar,
            onText: onVoskWakeText,
          );
          if (!started) await Future.delayed(const Duration(seconds: 3));
        }
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      // --- Repli : moteur Google ---
      if (!speechReady) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      if (foregroundBusy && speech.isListening && !handlingWakeWord) {
        await speech.stop();
      }
      if (!speech.isListening && !handlingWakeWord && !foregroundBusy) {
        try {
          await speech.listen(
            onResult: (result) {
              if (handlingWakeWord) return;
              final text = result.recognizedWords;
              final hasWake = containsWakeWord(text);
              final hasDirectCommand = detectIntent(text) != BankIntent.none;
              if (!wakeArmed && !hasWake && !hasDirectCommand) return;

              wakeArmed = true;
              wakeText = text;
              graceTimer?.cancel();
              if (result.finalResult) {
                fireWake();
              } else {
                graceTimer =
                    Timer(const Duration(milliseconds: 1100), fireWake);
              }
            },
            listenOptions: stt.SpeechListenOptions(
              listenMode: stt.ListenMode.confirmation,
              partialResults: true,
              cancelOnError: false,
              listenFor: const Duration(seconds: 55),
              pauseFor: const Duration(seconds: 8),
              localeId: 'fr_FR',
            ),
          );
        } catch (e) {
          debugPrint('[WakeWord] Erreur pendant l\'écoute: $e');
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        flnp.show(
          kForegroundNotifId,
          'BanqueParle actif',
          speech.isListening
              ? 'En écoute du mot-clé « Banque Parlante »…'
              : 'Reprise de l\'écoute…',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              kNotifChannelId,
              kNotifChannelName,
              icon: '@mipmap/ic_launcher',
              ongoing: true,
              importance: Importance.low,
              priority: Priority.low,
            ),
          ),
        );
      }
    }
  });

  // --- Synchronisation des donnees bancaires (copie locale) ---
  // Une premiere fois peu apres le demarrage, puis toutes les 2 minutes SI
  // une lecture a echoue faute de connexion, ou si la derniere
  // synchronisation date de plus de 20 minutes. Pas d'interrogation
  // continue : elle maintiendrait la base Neon eveillee en permanence
  // (quota du plan gratuit) et viderait la batterie.
  Future<void> syncIfNeeded({bool force = false}) async {
    try {
      final last = await LocalCache.lastSync();
      final stale = last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 20);
      if (force || stale || await LocalCache.needsSync()) {
        await SyncService.syncAll();
      }
    } catch (e) {
      debugPrint('[Sync] $e');
    }
  }

  unawaited(Future.delayed(
    const Duration(seconds: 20),
    () => syncIfNeeded(force: true),
  ));
  Timer.periodic(const Duration(minutes: 2), (_) => syncIfNeeded());

  listenLoop();
}

/// Déclenche le réveil visuel de l'application : notification plein écran
/// (comme un appel entrant), qui réveille l'écran et ouvre l'app SI le
/// système l'autorise (voir README : permission "Notifications plein
/// écran" à activer manuellement une fois sur Android 14+).
Future<void> _triggerAppWakeUp(
    FlutterLocalNotificationsPlugin flnp, ServiceInstance service) async {
  await flnp.show(
    kWakeNotifId,
    'BanqueParle',
    'Mot-clé détecté — Ouverture de l\'application…',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'banqueparle_wake_channel',
        'BanqueParle - Réveil',
        priority: Priority.max,
        importance: Importance.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        playSound: true,
      ),
    ),
  );
  service.invoke('wake_detected');
}
