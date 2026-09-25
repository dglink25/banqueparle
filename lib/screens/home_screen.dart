import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/tts_service.dart';
import '../services/stt_helper.dart';
import '../services/fingerprint_enrollment_flow.dart';
import '../services/voice_dialog.dart';
import '../utils/app_colors.dart';
import '../utils/onboarding_storage.dart';

enum _ScreenState { idle, onboardingName, fingerprintStep, listening }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription? _wakeSub;
  _ScreenState _state = _ScreenState.idle;
  String _statusText = 'Dites « Banque Parlante » pour commencer.';
  final stt.SpeechToText _speech = stt.SpeechToText();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.initialize();

    final service = FlutterBackgroundService();
    // Le service d'arrière-plan a déjà parlé (bienvenue, questions...) ;
    // ici on se contente de refléter visuellement l'état, SANS reparler,
    // pour éviter tout chevauchement de voix.
    _wakeSub = service.on('wake_detected').listen((event) {
      if (mounted) setState(() => _statusText = 'À l\'écoute…');
    });

    _checkPendingSteps(isColdStart: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wakeSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingSteps(isColdStart: false);
    }
  }

  /// Vérifie, à chaque ouverture/réapparition de l'app, s'il y a une étape
  /// en attente (empreinte digitale) et la lance. Sinon, ne joue le
  /// message de bienvenue générique QUE si le service d'arrière-plan ne
  /// vient pas déjà de parler (pour éviter un doublon de voix).
  Future<void> _checkPendingSteps({required bool isColdStart}) async {
    final needsFingerprint = await OnboardingStorage.needsFingerprintStep();

    if (needsFingerprint) {
      setState(() {
        _state = _ScreenState.fingerprintStep;
        _statusText = 'Configuration de votre empreinte digitale…';
      });
      final flow = FingerprintEnrollmentFlow(
        speak: TtsService.instance.speak,
        listen: () => sttListenOnce(_speech),
      );
      final success = await flow.run();
      if (mounted) {
        setState(() {
          _state = _ScreenState.idle;
          _statusText = success
              ? 'Enrôlement terminé. Dites « Banque Parlante » à tout moment.'
              : 'Redites « Banque Parlante » pour reprendre l\'enrôlement.';
        });
      }
      return;
    }

    final recentBgSpeech = await OnboardingStorage.wasBackgroundSpeechRecent();
    if (!recentBgSpeech) {
      // Ouverture manuelle (icône) : l'app peut se présenter elle-même.
      final completed = await OnboardingStorage.isCompleted();
      if (completed) {
        await TtsService.instance.speakWelcome();
      } else if (isColdStart) {
        // Premier lancement manuel, jamais passé par le mot-clé : on
        // propose de démarrer l'enrôlement directement depuis l'UI.
        await _runNameCollectionInForeground();
      }
    }
  }

  Future<void> _runNameCollectionInForeground() async {
    setState(() {
      _state = _ScreenState.onboardingName;
      _statusText = 'Enrôlement en cours…';
    });
    await TtsService.instance.speak(
      'Bienvenue sur Banque Parlante. Avant de commencer, j\'ai besoin '
      'de quelques informations.',
    );
    final name = await askWithRetry(
      speak: TtsService.instance.speak,
      listen: () => sttListenOnce(_speech),
      question: 'Quel est votre nom complet ?',
    );
    if (name != null) {
      await OnboardingStorage.setUserName(name);
      await TtsService.instance.speak(
        'Merci $name. Passons maintenant à la configuration de votre '
        'empreinte digitale.',
      );
      await OnboardingStorage.setNeedsFingerprintStep(true);
      if (mounted) await _checkPendingSteps(isColdStart: false);
    } else {
      if (mounted) {
        setState(() {
          _state = _ScreenState.idle;
          _statusText = 'Redites « Banque Parlante » pour continuer.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'BanqueParle',
                style: TextStyle(
                  color: AppColors.cream,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.creamFaint(0.75),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),
              _MicButton(active: _state != _ScreenState.idle),
              const SizedBox(height: 32),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.creamFaint(0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.podcasts,
                        color: AppColors.emerald, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Écoute active en arrière-plan',
                      style: TextStyle(color: AppColors.creamFaint(0.9)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => TtsService.instance.speakWelcome(),
                icon: const Icon(Icons.volume_up),
                label: const Text('Rejouer le message de bienvenue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => openAppSettings(),
                icon: Icon(Icons.settings, color: AppColors.creamFaint(0.8)),
                label: Text(
                  'Autoriser l\'ouverture automatique (réglages système)',
                  style: TextStyle(color: AppColors.creamFaint(0.8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final bool active;
  const _MicButton({required this.active});

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.emerald : AppColors.amber;
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: const Icon(Icons.mic, color: AppColors.navy, size: 56),
    );
  }
}
