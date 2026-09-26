import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/fingerprint_enrollment_flow.dart';
import '../services/onboarding_fields.dart';
import '../services/pin_enrollment_flow.dart';
import '../services/stt_helper.dart';
import '../services/tts_service.dart';
import '../services/voice_dialog.dart';
import '../utils/app_colors.dart';
import '../utils/onboarding_storage.dart';

const _settingsChannel = MethodChannel('com.banqueparle.banqueparle/settings');

enum _ScreenState { idle, formStep, securityStep }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription? _wakeSub;
  _ScreenState _state = _ScreenState.idle;
  String _statusText = 'Dites "Banque Parlante" pour commencer.';
  final stt.SpeechToText _speech = stt.SpeechToText();

  // Empeche deux executions simultanees du flux (par exemple si initState
  // et un evenement "resumed" se declenchent tous deux au demarrage, ce
  // qui arrive reellement sur Android lors d'un lancement a froid). Sans
  // ce verrou, deux instances du flux vocal / de la biometrie tournaient
  // en parallele et se melangeaient (double question, double invite
  // d'empreinte, audio superpose).
  bool _flowInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.initialize();

    final service = FlutterBackgroundService();
    // Le service d'arriere-plan a deja parle (bienvenue, questions...) ;
    // ici on se contente de refleter visuellement l'etat, sans reparler,
    // pour eviter tout chevauchement de voix.
    _wakeSub = service.on('wake_detected').listen((event) {
      if (mounted) setState(() => _statusText = 'A l\'ecoute...');
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

  /// Verifie, a chaque ouverture/reapparition de l'app, l'etape en attente
  /// et la lance. Ordre : formulaire (identite/compte) si incomplet, puis
  /// securite (empreinte, obligatoirement au premier plan, suivie du code
  /// secret obligatoire). Le message de bienvenue generique n'est joue que
  /// si le service d'arriere-plan ne vient pas deja de parler.
  Future<void> _checkPendingSteps({required bool isColdStart}) async {
    if (_flowInProgress) return; // verrou pose de facon synchrone, ici
    _flowInProgress = true;
    try {
      await OnboardingStorage.setFlowInProgress(true);

      final completed = await OnboardingStorage.isCompleted();
      if (completed) {
        final recentBgSpeech =
            await OnboardingStorage.wasBackgroundSpeechRecent();
        if (!recentBgSpeech) {
          await TtsService.instance.speakWelcome();
        }
        return;
      }

      final personalDone = await _allPresent(kPersonalInfoFields);
      final bankDone = await _allPresent(kBankAccountFields);

      if (!personalDone || !bankDone) {
        if (isColdStart) {
          await _runForm();
        }
        return;
      }

      final needsFingerprint = await OnboardingStorage.needsFingerprintStep();
      final needsPin = await OnboardingStorage.needsPinStep();
      if (needsFingerprint || needsPin) {
        await _runSecurity();
      }
    } finally {
      _flowInProgress = false;
      await OnboardingStorage.setFlowInProgress(false);
    }
  }

  Future<bool> _allPresent(List<OnboardingField> fields) async {
    for (final f in fields) {
      final v = await OnboardingStorage.getField(f.key);
      if (v == null || v.isEmpty) return false;
    }
    return true;
  }

  Future<void> _runForm() async {
    setState(() {
      _state = _ScreenState.formStep;
      _statusText = 'Enregistrement de vos informations...';
    });

    await TtsService.instance.speak(
      'Bienvenue sur Banque Parlante. Avant de commencer, j\'ai besoin '
      'de quelques informations pour ouvrir votre profil.',
    );

    final listenFn = () => sttListenOnce(_speech);

    final personalOk = await runFormFields(
      speak: TtsService.instance.speak,
      listen: listenFn,
      fields: kPersonalInfoFields,
    );
    final bankOk = personalOk &&
        await runFormFields(
          speak: TtsService.instance.speak,
          listen: listenFn,
          fields: kBankAccountFields,
        );

    if (personalOk && bankOk) {
      await OnboardingStorage.setNeedsFingerprintStep(true);
      await OnboardingStorage.setNeedsPinStep(true);
      await _runSecurity();
    } else {
      setState(() {
        _state = _ScreenState.idle;
        _statusText = 'Redites "Banque Parlante" pour continuer.';
      });
    }
  }

  Future<void> _runSecurity() async {
    setState(() {
      _state = _ScreenState.securityStep;
      _statusText = 'Configuration de la securite de votre compte...';
    });

    final needsFingerprint = await OnboardingStorage.needsFingerprintStep();
    if (needsFingerprint) {
      final fingerprintFlow = FingerprintEnrollmentFlow(
        speak: TtsService.instance.speak,
        listen: () => sttListenOnce(_speech),
      );
      await fingerprintFlow.run();
    }

    final needsPin = await OnboardingStorage.needsPinStep();
    if (needsPin) {
      final pinFlow = PinEnrollmentFlow(
        speak: TtsService.instance.speak,
        listen: () => sttListenOnce(_speech),
      );
      final pinOk = await pinFlow.run();
      if (pinOk) {
        final name = await OnboardingStorage.getField('full_name');
        await OnboardingStorage.setCompleted(true);
        final greetingName = (name != null && name.isNotEmpty) ? ' $name' : '';
        await TtsService.instance.speak(
          'Bienvenue$greetingName. Votre enrolement est termine. '
          'Vous pouvez maintenant utiliser Banque Parlante.',
        );
      }
    }

    if (mounted) {
      final completed = await OnboardingStorage.isCompleted();
      setState(() {
        _state = _ScreenState.idle;
        _statusText = completed
            ? 'Dites "Banque Parlante" a tout moment.'
            : 'Redites "Banque Parlante" pour terminer la securite.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'BanqueParle',
                style: TextStyle(
                  color: AppColors.blue,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.blue, fontSize: 16),
              ),
              const SizedBox(height: 48),
              _MicButton(active: _state != _ScreenState.idle),
              const SizedBox(height: 32),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  border: Border.all(color: AppColors.blue, width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Ecoute active en arriere-plan',
                  style: TextStyle(color: AppColors.blue),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => TtsService.instance.speakWelcome(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('Rejouer le message de bienvenue'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    _settingsChannel.invokeMethod('openFullScreenIntentSettings'),
                child: const Text(
                  'Autoriser l\'ouverture automatique (reglages systeme)',
                  style: TextStyle(color: AppColors.blue),
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
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.blue : AppColors.white,
        border: Border.all(color: AppColors.blue, width: 3),
      ),
      child: Icon(
        Icons.mic,
        color: active ? AppColors.white : AppColors.blue,
        size: 56,
      ),
    );
  }
}
