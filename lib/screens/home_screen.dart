import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/account_provisioning_service.dart';
import '../services/advisor_flow.dart';
import '../services/auth_gate.dart';
import '../services/balance_flow.dart';
import '../services/command_intent.dart';
import '../services/fingerprint_enrollment_flow.dart';
import '../services/flow_control.dart';
import '../services/history_flow.dart';
import '../services/onboarding_fields.dart';
import '../services/otp_flow.dart';
import '../services/pin_enrollment_flow.dart';
import '../services/profile_flow.dart';
import '../services/stop_command.dart';
import '../services/stt_helper.dart';
import '../services/transfer_flow.dart';
import '../services/tts_service.dart';
import '../services/voice_dialog.dart';
import '../utils/app_colors.dart';
import '../utils/native_channel.dart';
import '../utils/onboarding_storage.dart';

enum _ScreenState { idle, formStep, securityStep, action }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription? _wakeSub;
  StreamSubscription? _quitSub;
  Timer? _heardTimer;
  String _lastHeard = '';
  String _lastDbError = '';
  _ScreenState _state = _ScreenState.idle;
  BankIntent _activeIntent = BankIntent.none;
  bool _enrolled = false;
  String _statusText = 'Dites "Banque Parlante" pour commencer.';
  final stt.SpeechToText _speech = stt.SpeechToText();

  // Verrou du controle d'enrolement : empeche deux executions simultanees
  // (initState et un evenement "resumed" se declenchent tous deux au
  // demarrage a froid sur Android).
  bool _flowInProgress = false;

  // Execution des commandes bancaires. Une nouvelle commande (appui sur
  // une touche) interrompt la precedente : la voix est coupee, l'ecoute
  // et l'invite biometrique sont annulees, puis la nouvelle demarre.
  bool _actionRunning = false;
  int _requestSeq = 0;
  CancelToken? _activeToken;
  Future<void>? _activeRun;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.initialize();
    _refreshEnrolled();

    final service = FlutterBackgroundService();
    _wakeSub = service.on('wake_detected').listen((event) {
      if (!mounted) return;
      _checkPendingSteps(isColdStart: false);
    });
    // Commande "quitter" dite apres le mot-cle : le service d'arriere-plan
    // a deja prononce l'au revoir, l'interface se ferme sans reparler.
    _quitSub = service.on('quit_requested').listen((event) {
      _closeSession(announce: false);
    });

    // Diagnostic : relit regulierement la derniere phrase entendue (ecrite
    // aussi par le service d'arriere-plan, d'ou la relecture du disque).
    _heardTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final heard = await OnboardingStorage.getLastHeard();
      final dbError = await OnboardingStorage.getLastDbError();
      if (mounted && (heard != _lastHeard || dbError != _lastDbError)) {
        setState(() {
          _lastHeard = heard;
          _lastDbError = dbError;
        });
      }
    });

    _checkPendingSteps(isColdStart: true);
  }

  @override
  void dispose() {
    _heardTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _wakeSub?.cancel();
    _quitSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingSteps(isColdStart: false);
    }
  }

  Future<void> _refreshEnrolled() async {
    final done = await OnboardingStorage.isCompleted();
    if (mounted && done != _enrolled) setState(() => _enrolled = done);
  }

  // ---------------------------------------------------------------------
  // Enrolement et reprise
  // ---------------------------------------------------------------------

  Future<void> _checkPendingSteps({required bool isColdStart}) async {
    if (_flowInProgress || _actionRunning) return;
    _flowInProgress = true;
    try {
      await OnboardingStorage.setFlowInProgress(true);

      final completed = await OnboardingStorage.isCompleted();
      if (completed) {
        await _refreshEnrolled();
        final pending = await OnboardingStorage.getPendingAction();
        if (pending != null) {
          // Consomme l'action immediatement : un second declenchement
          // (reprise de l'app) ne doit jamais la rejouer.
          await OnboardingStorage.setPendingAction(null);
          final intent = BankIntent.values.firstWhere(
            (i) => i.name == pending,
            orElse: () => BankIntent.none,
          );
          if (intent != BankIntent.none) {
            unawaited(_startAction(intent));
            return;
          }
        }
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
          await _runStoppable(null, _runForm);
        }
        return;
      }

      final needsFingerprint = await OnboardingStorage.needsFingerprintStep();
      final needsPin = await OnboardingStorage.needsPinStep();
      if (needsFingerprint || needsPin) {
        await _runStoppable(null, _runSecurity);
      }
    } finally {
      _flowInProgress = false;
      // Si une commande vient de demarrer, c'est elle qui libere le
      // drapeau partage a sa fin : ne pas le relacher ici.
      if (!_actionRunning) {
        await OnboardingStorage.setFlowInProgress(false);
      }
    }
  }

  Future<bool> _allPresent(List<OnboardingField> fields) async {
    for (final f in fields) {
      final v = await OnboardingStorage.getField(f.key);
      if (v == null || v.isEmpty) return false;
    }
    return true;
  }

  /// Cree, si ce n'est pas deja fait, le role bancaire dedie du client sur
  /// Neon. Renvoie true si le compte est pret pour les operations.
  Future<bool> _ensureProvisioned({SpeakFn? speak}) async {
    final say = speak ?? TtsService.instance.speak;
    if (await OnboardingStorage.isAccountProvisioned() &&
        await AccountProvisioningService.isProvisioned()) {
      return true;
    }

    final accountNumber = await OnboardingStorage.getField('account_number');
    final ownerName = await OnboardingStorage.getField('full_name');
    if (accountNumber == null || ownerName == null) return false;

    await say('Activation de votre compte bancaire en cours.');
    final result = await AccountProvisioningService.provision(
      accountNumber: accountNumber,
      ownerName: ownerName,
    );
    await say(result.message);
    if (result.success) {
      await OnboardingStorage.setAccountProvisioned(true);
    }
    return result.success;
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

    final listenFn = _listenFor(null);

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

    // Active le compte bancaire cote base de donnees. En cas d'echec
    // (pas de connexion), l'enrolement continue ; l'activation sera
    // retentee automatiquement a la premiere operation bancaire.
    await _ensureProvisioned();

    final needsFingerprint = await OnboardingStorage.needsFingerprintStep();
    if (needsFingerprint) {
      final fingerprintFlow = FingerprintEnrollmentFlow(
        speak: TtsService.instance.speak,
        listen: _listenFor(null),
      );
      await fingerprintFlow.run();
    }

    final needsPin = await OnboardingStorage.needsPinStep();
    if (needsPin) {
      final pinFlow = PinEnrollmentFlow(
        speak: TtsService.instance.speak,
        listen: _listenFor(null),
      );
      final pinOk = await pinFlow.run();
      if (pinOk) {
        final name = await OnboardingStorage.getField('full_name');
        await OnboardingStorage.setCompleted(true);
        final greetingName = (name != null && name.isNotEmpty) ? ' $name' : '';
        await TtsService.instance.speak(
          'Bienvenue$greetingName. Votre enrolement est termine. '
          'Utilisez le pave numerique a l\'ecran, ou dites "Banque '
          'Parlante" suivi de votre demande.',
        );
      }
    }

    await _refreshEnrolled();
    if (mounted) {
      setState(() {
        _state = _ScreenState.idle;
        _statusText = _enrolled
            ? 'Dites "Banque Parlante" ou utilisez le pave numerique.'
            : 'Redites "Banque Parlante" pour terminer la securite.';
      });
    }
  }

  // ---------------------------------------------------------------------
  // Commandes bancaires (touches 1 a 6 et 0)
  // ---------------------------------------------------------------------

  SpeakFn _speakFor(CancelToken? t) => (String text) async {
        t?.throwIfCancelled();
        await TtsService.instance.speak(text);
        t?.throwIfCancelled();
      };

  /// Ecoute brute, sans interception de l'arret : utilisee pour la question
  /// de confirmation de l'arret elle-meme.
  ListenFn _rawListenFor(CancelToken? t) => () async {
        t?.throwIfCancelled();
        final result = await sttListenOnce(
          _speech,
          shouldStop: () => t?.isCancelled ?? false,
        );
        t?.throwIfCancelled();
        return result;
      };

  /// Ecoute des parcours : dire "stop", "arrete" ou "zero" coupe l'activite
  /// au lieu d'etre pris pour une reponse (nom, montant, numero...).
  ListenFn _listenFor(CancelToken? t) => interceptStop(_rawListenFor(t));

  /// Demande confirmation de l'arret. Sans reponse claire, l'arret est
  /// execute : l'utilisateur l'a demande, il peut s'agir d'une urgence.
  Future<bool> _confirmStop(CancelToken? t) async {
    final answer = await askYesNo(
      speak: _speakFor(t),
      listen: _rawListenFor(t),
      question: kStopConfirmQuestion,
      maxAttempts: 3,
    );
    return answer != false;
  }

  Future<void> _performStop(CancelToken? t) async {
    await _speakFor(t)(kStoppedMessage);
    await _closeSession(announce: false);
  }

  /// Execute [body]. Si l'utilisateur demande l'arret, demande confirmation :
  /// s'il confirme, l'application s'arrete (retour true) ; sinon l'activite
  /// reprend depuis le debut de ce parcours. Les champs deja enregistres a
  /// l'enrolement ne sont jamais redemandes.
  Future<bool> _runStoppable(
    CancelToken? t,
    Future<void> Function() body,
  ) async {
    while (true) {
      try {
        await body();
        return false;
      } on StopRequested {
        if (await _confirmStop(t)) {
          await _performStop(t);
          return true;
        }
        await _speakFor(t)('D\'accord, on reprend.');
      }
    }
  }

  Future<void> _onKey(KeyDef key) async {
    HapticFeedback.mediumImpact();
    if (!_enrolled) return; // le pave n'est actif qu'apres l'enrolement
    unawaited(_startAction(key.intent));
  }

  Future<void> _startAction(BankIntent intent) async {
    final myId = ++_requestSeq;

    // Activite en cours au moment de l'appui. Si l'appui est sur "0"
    // (arret) et que l'utilisateur refuse ensuite d'arreter, cette
    // activite reprendra.
    final interrupted = (_actionRunning && _activeIntent != BankIntent.quit)
        ? _activeIntent
        : BankIntent.none;
    _actionRunning = true;

    // Interrompt immediatement ce qui est en cours.
    _activeToken?.cancel();
    await TtsService.instance.stop();
    try {
      await _speech.cancel();
    } catch (_) {}
    await AuthGate.cancelPrompt();

    final previous = _activeRun;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    if (myId != _requestSeq) return; // une commande plus recente a pris le relais

    final token = CancelToken();
    _activeToken = token;
    final run = _executeAction(intent, token, myId, resume: interrupted);
    _activeRun = run;
    await run;
  }

  String _statusFor(BankIntent intent) {
    switch (intent) {
      case BankIntent.balance:
        return 'Consultation du solde...';
      case BankIntent.history:
        return 'Historique des operations...';
      case BankIntent.transfer:
        return 'Virement en cours...';
      case BankIntent.otp:
        return 'Code de securite...';
      case BankIntent.profile:
        return 'Gestion du profil...';
      case BankIntent.advisor:
        return 'Appel du conseiller...';
      case BankIntent.quit:
        return 'Arret de Banque Parlante...';
      case BankIntent.none:
        return '';
    }
  }

  /// Corps d'une commande bancaire (hors arret).
  Future<void> _runIntent(
    BankIntent intent,
    SpeakFn speak,
    ListenFn listen,
  ) async {
    switch (intent) {
      case BankIntent.advisor:
        await AdvisorFlow(speak: speak).run();
        break;

      case BankIntent.profile:
        await ProfileFlow(speak: speak, listen: listen).run();
        break;

      case BankIntent.balance:
      case BankIntent.history:
      case BankIntent.transfer:
      case BankIntent.otp:
        if (!await _ensureProvisioned(speak: speak)) {
          await speak(
            'Votre compte bancaire n\'est pas encore active. Verifiez '
            'votre connexion internet puis reessayez.',
          );
          break;
        }
        if (intent == BankIntent.balance) {
          await BalanceFlow(speak: speak, listen: listen).run();
        } else if (intent == BankIntent.history) {
          await HistoryFlow(speak: speak, listen: listen).run();
        } else if (intent == BankIntent.transfer) {
          await TransferFlow(speak: speak, listen: listen).run();
        } else {
          await OtpFlow(speak: speak, listen: listen).run();
        }
        break;

      case BankIntent.quit:
      case BankIntent.none:
        break;
    }
  }

  Future<void> _executeAction(
    BankIntent intent,
    CancelToken token,
    int myId, {
    BankIntent resume = BankIntent.none,
  }) async {
    final speak = _speakFor(token);
    final listen = _listenFor(token);

    await OnboardingStorage.setFlowInProgress(true);
    if (mounted) {
      setState(() {
        _state = _ScreenState.action;
        _activeIntent = intent;
        _statusText = _statusFor(intent);
      });
    }

    try {
      if (intent == BankIntent.quit) {
        // Touche 0 : l'activite en cours est deja coupee. Confirmation,
        // puis arret ; si l'utilisateur refuse, on reprend l'activite.
        if (await _confirmStop(token)) {
          await _performStop(token);
          return;
        }
        if (resume == BankIntent.none) {
          await speak('D\'accord, Banque Parlante reste actif.');
        } else {
          await speak('D\'accord, on reprend.');
          if (mounted) {
            setState(() {
              _activeIntent = resume;
              _statusText = _statusFor(resume);
            });
          }
          final stopped = await _runStoppable(
            token,
            () => _runIntent(resume, speak, listen),
          );
          if (stopped) return;
        }
      } else {
        final stopped = await _runStoppable(
          token,
          () => _runIntent(intent, speak, listen),
        );
        if (stopped) return;
      }
    } on FlowCancelled {
      // Interrompu par l'appui sur une autre touche : rien a faire.
    } catch (_) {
      try {
        await TtsService.instance.speak(
          'Une erreur est survenue. Veuillez reessayer.',
        );
      } catch (_) {}
    } finally {
      // Seule la commande la plus recente libere l'etat partage.
      if (myId == _requestSeq) {
        _actionRunning = false;
        _activeIntent = BankIntent.none;
        await OnboardingStorage.setFlowInProgress(false);
        if (mounted) {
          setState(() {
            _state = _ScreenState.idle;
            _statusText =
                'Dites "Banque Parlante" ou utilisez le pave numerique.';
          });
        }
      }
    }
  }

  /// Ferme l'ecran et renvoie l'application en arriere-plan.
  ///
  /// L'application ne conserve aucun etat authentifie : chaque operation
  /// sensible redemande l'identite. Fermer la session consiste donc a
  /// couper voix, ecoute et invite biometrique, a liberer les drapeaux
  /// partages, puis a fermer l'ecran. Le service d'arriere-plan continue
  /// d'ecouter le mot-cle : c'est le "retour en mode veille", et dire
  /// "Banque Parlante" relance l'application.
  Future<void> _closeSession({required bool announce}) async {
    _requestSeq++;
    _activeToken?.cancel();
    await TtsService.instance.stop();
    try {
      await _speech.cancel();
    } catch (_) {}
    await AuthGate.cancelPrompt();

    if (announce) {
      try {
        await TtsService.instance.speak(kStoppedMessage);
      } catch (_) {}
    }

    await OnboardingStorage.setPendingAction(null);
    await OnboardingStorage.setFlowInProgress(false);
    _actionRunning = false;
    await SystemNavigator.pop();
  }

  // ---------------------------------------------------------------------
  // Interface : deux couleurs uniquement (bleu et blanc)
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final busy = _state != _ScreenState.idle;
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              const Text(
                'BanqueParle',
                style: TextStyle(
                  color: AppColors.blue,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.blue, fontSize: 15),
              ),
              if (_lastHeard.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Derniere phrase entendue : "$_lastHeard"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.blue, fontSize: 12),
                ),
              ],
              if (_lastDbError.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Derniere erreur base : $_lastDbError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.blue, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              _MicIndicator(active: busy),
              const SizedBox(height: 16),
              _Keypad(
                enabled: _enrolled,
                activeIntent: _activeIntent,
                onKey: _onKey,
              ),
              const SizedBox(height: 12),
              if (!_enrolled)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Le pave numerique sera disponible apres l\'enrolement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.blue, fontSize: 13),
                  ),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  border: Border.all(color: AppColors.blue, width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Ecoute active en arriere-plan',
                  style: TextStyle(color: AppColors.blue, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    kNativeChannel.invokeMethod('openFullScreenIntentSettings'),
                child: const Text(
                  'Autoriser l\'ouverture automatique (reglages systeme)',
                  textAlign: TextAlign.center,
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

class _MicIndicator extends StatelessWidget {
  final bool active;
  const _MicIndicator({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.blue : AppColors.white,
        border: Border.all(color: AppColors.blue, width: 3),
      ),
      child: Icon(
        Icons.mic,
        color: active ? AppColors.white : AppColors.blue,
        size: 40,
      ),
    );
  }
}

/// Pave numerique geant de secours (cahier des charges, section 3.2) :
/// un appui interrompt la voix et execute immediatement la commande.
class _Keypad extends StatelessWidget {
  final bool enabled;
  final BankIntent activeIntent;
  final Future<void> Function(KeyDef) onKey;

  const _Keypad({
    required this.enabled,
    required this.activeIntent,
    required this.onKey,
  });

  Widget _cell(KeyDef k) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: _KeyButton(
            def: k,
            enabled: enabled,
            active: activeIntent == k.intent,
            onTap: () => onKey(k),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final zero = kKeypad.firstWhere((k) => k.key == '0');
    return Column(
      children: [
        Row(children: [_cell(kKeypad[0]), _cell(kKeypad[1]), _cell(kKeypad[2])]),
        Row(children: [_cell(kKeypad[3]), _cell(kKeypad[4]), _cell(kKeypad[5])]),
        Row(children: [
          const Expanded(child: SizedBox()),
          _cell(zero),
          const Expanded(child: SizedBox()),
        ]),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final KeyDef def;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  const _KeyButton({
    required this.def,
    required this.enabled,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = active ? AppColors.white : AppColors.blue;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Touche ${def.key}, ${def.label}',
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: Material(
            color: active ? AppColors.blue : AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppColors.blue, width: 2.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: AspectRatio(
                aspectRatio: 1.15,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      def.key,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      def.label,
                      style: TextStyle(color: foreground, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
