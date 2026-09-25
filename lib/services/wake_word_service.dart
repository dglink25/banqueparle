import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../utils/onboarding_storage.dart';
import 'stt_helper.dart';
import 'voice_dialog.dart';

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
///      (collecte du nom) intégralement en arrière-plan, sans dépendre
///      de l'interface.
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

String normalize(String input) {
  const withAccents = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const withoutAccents = 'aaaaaaceeeeiiiinooooouuuuyy';
  var out = input.toLowerCase();
  for (var i = 0; i < withAccents.length; i++) {
    out = out.replaceAll(withAccents[i], withoutAccents[i]);
  }
  out = out.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

bool containsWakeWord(String recognized) {
  final norm = normalize(recognized);
  for (final variant in kWakeVariants) {
    if (norm.contains(normalize(variant))) return true;
  }
  return false;
}

/// Initialise le service d'arrière-plan (à appeler une seule fois, dans main()).
Future<void> initializeWakeWordService() async {
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
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: kNotifChannelId,
      initialNotificationTitle: 'BanqueParle',
      initialNotificationContent: 'Écoute du mot-clé « Banque Parlante »…',
      foregroundServiceNotificationId: kForegroundNotifId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onServiceStart,
      onBackground: (service) async => true,
    ),
  );

  await service.startService();
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
    await tts.speak(text);
    // Attend la fin de la lecture pour ne pas enchaîner les phrases.
    final completer = Completer<void>();
    tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  bool speechReady = await speech.initialize(
    onError: (e) => debugPrint('[WakeWord] Erreur STT: $e'),
    onStatus: (status) => debugPrint('[WakeWord] Statut STT: $status'),
  );

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    speech.stop();
    service.stopSelf();
  });

  if (!speechReady) {
    debugPrint('[WakeWord] speech_to_text indisponible sur cet appareil.');
    return;
  }

  bool handlingWakeWord = false; // évite les déclenchements concurrents

  Future<void> handleWakeWordDetected() async {
    if (handlingWakeWord) return;
    handlingWakeWord = true;
    try {
      await speech.stop();
      final completed = await OnboardingStorage.isCompleted();

      if (!completed) {
        final existingName = await OnboardingStorage.getUserName();

        if (existingName == null || existingName.isEmpty) {
          // --- Étape 1 : collecte du nom, entièrement headless ---
          await speak(
            'Bienvenue sur Banque Parlante. Avant de commencer, '
            'j\'ai besoin de quelques informations.',
          );
          await OnboardingStorage.markBackgroundSpeech();

          final name = await askWithRetry(
            speak: speak,
            listen: () => sttListenOnce(speech),
            question: 'Quel est votre nom complet ?',
          );

          if (name == null) {
            await speak(
              'Je n\'ai pas réussi à vous entendre. Redites '
              '« Banque Parlante » quand vous serez prêt à continuer.',
            );
            await OnboardingStorage.markBackgroundSpeech();
          } else {
            await OnboardingStorage.setUserName(name);
            await speak(
              'Merci $name. Pour terminer votre inscription, ouvrez '
              'votre téléphone : l\'application va s\'ouvrir pour '
              'configurer votre empreinte digitale.',
            );
            await OnboardingStorage.setNeedsFingerprintStep(true);
            await OnboardingStorage.markBackgroundSpeech();
            await _triggerAppWakeUp(flnp, service);
          }
        } else if (await OnboardingStorage.needsFingerprintStep()) {
          // --- Nom déjà connu, empreinte pas encore configurée ---
          await speak(
            'Il reste à configurer votre empreinte digitale, $existingName. '
            'Merci d\'ouvrir votre téléphone.',
          );
          await OnboardingStorage.markBackgroundSpeech();
          await _triggerAppWakeUp(flnp, service);
        }
      } else {
        // --- Utilisation normale (enrôlement déjà terminé) ---
        final name = await OnboardingStorage.getUserName();
        final greeting = (name != null && name.isNotEmpty)
            ? 'Bienvenue $name. Je vous écoute.'
            : 'Bienvenue sur Banque Parlante. Je vous écoute.';
        await speak(greeting);
        await OnboardingStorage.markBackgroundSpeech();
        await _triggerAppWakeUp(flnp, service);
        service.invoke('wake_detected');
      }
    } catch (e) {
      debugPrint('[WakeWord] Erreur pendant le traitement du mot-clé: $e');
    } finally {
      handlingWakeWord = false;
    }
  }

  Future<void> listenLoop() async {
    while (true) {
      if (!speech.isListening && !handlingWakeWord) {
        try {
          await speech.listen(
            onResult: (result) async {
              final text = result.recognizedWords;
              if (containsWakeWord(text)) {
                debugPrint('[WakeWord] ✅ Mot-clé détecté !');
                await speech.stop();
                await handleWakeWordDetected();
              }
            },
            listenFor: const Duration(seconds: 55),
            pauseFor: const Duration(seconds: 8),
            partialResults: true,
            localeId: 'fr_FR',
            listenMode: stt.ListenMode.confirmation,
          );
        } catch (e) {
          debugPrint('[WakeWord] Erreur pendant l\'écoute: $e');
        }
      }
      await Future.delayed(const Duration(seconds: 2));
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
