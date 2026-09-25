import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// -----------------------------------------------------------------------
/// WakeWordService
///
/// Ce service tourne en Foreground Service Android (notification
/// persistante) et écoute en continu le microphone via speech_to_text.
/// Dès que la phrase "banque parlante" (ou une variante phonétique proche)
/// est reconnue, il :
///   1. Affiche une notification "Full-Screen Intent" qui réveille
///      l'écran et ramène l'application au premier plan (comme un appel
///      entrant), MÊME si le téléphone est verrouillé.
///   2. Envoie un signal à l'UI (si déjà ouverte) pour déclencher
///      immédiatement le message de bienvenue vocal.
/// -----------------------------------------------------------------------

const String kNotifChannelId = 'banqueparle_wakeword_channel';
const String kNotifChannelName = 'BanqueParle - Écoute active';
const int kForegroundNotifId = 888;
const int kWakeNotifId = 999;

/// Mots-clés déclencheurs et variantes phonétiques / homophones tolérées
/// (le cahier des charges impose la gestion des homophones du français).
const List<String> kWakeVariants = [
  'banque parlante',
  'banc parlant',
  'banque parlant',
  'banc parlante',
  'banque parle',
  'ma banque parlante',
];

/// Normalise une chaîne : minuscules, sans accents, espaces multiples réduits.
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

/// Vérifie si le texte reconnu contient une variante du mot-clé.
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

  // Canal pour la notification persistante du service (discrète)
  const serviceChannel = AndroidNotificationChannel(
    kNotifChannelId,
    kNotifChannelName,
    description: 'Indique que BanqueParle écoute le mot-clé en arrière-plan.',
    importance: Importance.low,
  );

  // Canal pour la notification de réveil (bruyante, plein écran, comme un appel)
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

  // Boucle d'écoute continue : speech_to_text s'arrête après un silence
  // ou une durée max, donc on la relance en continu tant que le service vit.
  Future<void> listenLoop() async {
    while (true) {
      if (!speech.isListening) {
        try {
          await speech.listen(
            onResult: (result) async {
              final text = result.recognizedWords;
              debugPrint('[WakeWord] Entendu: "$text"');
              if (containsWakeWord(text)) {
                debugPrint('[WakeWord] ✅ Mot-clé détecté !');
                await speech.stop();
                await _triggerAppWakeUp(flnp, service);
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

  // Ping périodique pour garder le service visible / vivant et mettre
  // à jour la notification persistante avec un statut clair.
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        flnp.show(
          kForegroundNotifId,
          'BanqueParle actif',
          speech.isListening
              ? 'En écoute du mot-clé « Banque Parlante »…'
              : 'Reprise de l\'écoute…',
          NotificationDetails(
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

/// Déclenche le réveil de l'application : notification plein écran
/// (comme un appel entrant) + tentative de lancement direct de l'activité.
Future<void> _triggerAppWakeUp(
    FlutterLocalNotificationsPlugin flnp, ServiceInstance service) async {
  // 1. Notification "Full-Screen Intent" : réveille l'écran même verrouillé
  //    et ouvre l'app au tap (comportement standard Android pour ce cas
  //    d'usage, utilisé par les apps d'appel/alarme).
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

  // 2. Informe l'UI (si déjà visible en mémoire) qu'il faut jouer le
  //    message de bienvenue immédiatement, sans attendre le tap sur la
  //    notification.
  service.invoke('wake_detected');
}
