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
import '../services/grammars.dart';
import '../services/history_flow.dart';
import '../services/onboarding_fields.dart';
import '../services/otp_flow.dart';
import '../services/pin_enrollment_flow.dart';
import '../services/profile_flow.dart';
import '../services/local_cache.dart';
import '../services/stop_command.dart';
import '../services/sync_service.dart';
import '../services/stt_helper.dart';
import '../services/transfer_flow.dart';
import '../services/tts_service.dart';
import '../services/voice_dialog.dart';
import '../services/vosk_engine.dart';
import '../services/vosk_guard.dart';
import '../services/wake_word_service.dart';
import '../utils/app_colors.dart';
import '../utils/native_channel.dart';
import '../utils/onboarding_storage.dart';
import '../utils/permissions_helper.dart';

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
  String _voiceStatus = '';
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

    // Initialisation post-frame sécurisée : attend que l'Activity Android
    // soit attachée et que l'écran soit affiché pour demander les autorisations.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServicesAndPermissions();
    });

    _refreshEnrolled();

    try {
      final service = FlutterBackgroundService();
      _wakeSub = service.on('wake_detected').listen((event) {
        if (!mounted) return;
        _checkPendingSteps(isColdStart: false);
      });
      // Commande "quitter" dite apres le mot-cle : le service d'arriere-plan
      // a deja prononce l'au revoir, l'interface se remet en veille sans reparler.
      _quitSub = service.on('quit_requested').listen((event) {
        _closeSession(announce: false);
      });
    } catch (_) {}

    // Diagnostic : relit regulierement la derniere phrase entendue
    _heardTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final heard = await OnboardingStorage.getLastHeard();
        final dbError = await OnboardingStorage.getLastDbError();
        final voice = await OnboardingStorage.getVoiceStatus();
        if (mounted &&
            (heard != _lastHeard ||
                dbError != _lastDbError ||
                voice != _voiceStatus)) {
          setState(() {
            _lastHeard = heard;
            _lastDbError = dbError;
            _voiceStatus = voice;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _initializeServicesAndPermissions() async {
    // 0. Réinitialise tout état de verrouillage Vosk pour donner priorité au moteur hors ligne
    try {
      await VoskGuard.reset();
      await VoskGuard.inspect();
    } catch (e) {
      debugPrint('[Init] VoskGuard reset error: $e');
    }

    // 1. Initialise le TTS (prépare le moteur de synthèse vocale)
    try {
      await TtsService.instance.init();
    } catch (e) {
      debugPrint('[Init] TTS init error: $e');
    }

    // 2. Demande des permissions nécessaires (micro, notifications, batterie)
    //    avec l'interface utilisateur déjà affichée et l'Activity Android attachée.
    bool micOk = false;
    try {
      micOk = await PermissionsHelper.requestAll();
    } catch (e) {
      debugPrint('[Init] Permissions error: $e');
    }

    // 3. Configure le service d'arrière-plan et le démarre SI le micro est autorisé
    try {
      await initializeWakeWordService();
      if (micOk) {
        await startWakeWordServiceIfPermitted();
      }
    } catch (e) {
      debugPrint('[Init] WakeWordService error: $e');
    }

    // 4. Met en pause l'écoute d'arrière-plan pour que le premier plan ait le contrôle exclusif du micro
    try {
      FlutterBackgroundService().invoke('pause_wake');
    } catch (_) {}

    // 5. Initialise le moteur Google de repli
    try {
      await _speech.initialize(onError: (e) {
        final message = e.errorMsg;
        if (message != 'error_no_match' && message != 'error_speech_timeout') {
          unawaited(OnboardingStorage.setLastHeard(
            '(erreur du moteur Google : $message)',
          ));
        }
      });
    } catch (e) {
      debugPrint('[Init] Speech initialize error: $e');
    }

    // 6. Extraction différée du modèle Vosk hors ligne
    unawaited(Future.delayed(
      const Duration(seconds: 4),
      () => VoskEngine.prepareModelFromAssets(),
    ));

    // 7. Vérifie les étapes d'enrôlement ou lance le dialogue vocal
    if (mounted) {
      _checkPendingSteps(isColdStart: true);
    }
  }

  @override
  void dispose() {
    _heardTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _wakeSub?.cancel();
    _quitSub?.cancel();
    try {
      FlutterBackgroundService().invoke('resume_wake');
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        FlutterBackgroundService().invoke('pause_wake');
      } catch (_) {}
      _checkPendingSteps(isColdStart: false);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      try {
        unawaited(startWakeWordServiceIfPermitted());
        FlutterBackgroundService().invoke('resume_wake');
      } catch (_) {}
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
        // Synchronisation en temps réel dès l'arrivée à l'écran
        unawaited(SyncService.syncAll());
        // Lancement direct de la boucle de dialogue 100% vocale
        unawaited(_runVocalLoop(isWelcome: true));
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
      // Envoie le profil saisi a l'enrolement (telephone, date de
      // naissance, type de compte) puis fait une premiere synchronisation.
      final sent = await SyncService.pushLocalProfile();
      if (!sent) await LocalCache.setProfileDirty(true);
      unawaited(SyncService.syncAll());
    }
    return result.success;
  }

  Future<void> _runForm() async {
    setState(() {
      _state = _ScreenState.formStep;
      _statusText = 'Enregistrement de vos informations...';
    });

    await OnboardingStorage.setFlowInProgress(true);
    try {
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
    } finally {
      if (_state != _ScreenState.securityStep && !_actionRunning) {
        await OnboardingStorage.setFlowInProgress(false);
      }
    }
  }

  Future<void> _runSecurity() async {
    setState(() {
      _state = _ScreenState.securityStep;
      _statusText = 'Configuration de la sécurité de votre compte...';
    });

    await OnboardingStorage.setFlowInProgress(true);
    try {
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
            'Bienvenue$greetingName. Votre sécurité est configurée. '
            'Votre compte est prêt.',
          );
          await _refreshEnrolled();
          unawaited(_runVocalLoop(isWelcome: true));
          return;
        }
      }

      await _refreshEnrolled();
      if (mounted) {
        setState(() {
          _state = _ScreenState.idle;
          _statusText = _enrolled
              ? 'Mode 100% vocal actif. Dites votre demande.'
              : 'Redites "Banque Parlante" pour terminer la sécurité.';
        });
      }
    } finally {
      if (!_actionRunning) {
        await OnboardingStorage.setFlowInProgress(false);
      }
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

  /// Demande confirmation de l'arret. Sans reponse claire ou en cas de silence,
  /// l'arret N'EST PAS execute afin d'eviter toute fermeture intempestive.
  Future<bool> _confirmStop(CancelToken? t) async {
    final answer = await askYesNo(
      speak: _speakFor(t),
      listen: _rawListenFor(t),
      question: kStopConfirmQuestion,
      maxAttempts: 3,
    );
    return answer == true;
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
        return 'Historique des opérations...';
      case BankIntent.transfer:
        return 'Virement en cours...';
      case BankIntent.otp:
        return 'Code de sécurité...';
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
            'Votre compte bancaire n\'est pas encore activé. Vérifiez '
            'votre connexion internet puis réessayez.',
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

        // Une fois l'opération terminée, l'application ne s'arrête pas :
        // elle demande vocalement à l'utilisateur s'il souhaite faire autre chose
        if (mounted && myId == _requestSeq) {
          await _askFollowUp(token, speak, listen);
          return;
        }
      }
    } on FlowCancelled {
      // Interrompu par l'appui sur une autre touche : rien a faire.
    } catch (_) {
      try {
        await TtsService.instance.speak(
          'Une erreur est survenue. Veuillez réessayer.',
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
            _statusText = 'Mode 100% vocal actif. Dites votre demande.';
          });
        }
      }
    }
  }

  /// Propose vocalement à l'utilisateur de continuer ou de quitter après une opération
  Future<void> _askFollowUp(
    CancelToken token,
    SpeakFn speak,
    ListenFn listen,
  ) async {
    if (!mounted) return;
    setState(() {
      _activeIntent = BankIntent.none;
      _statusText = 'Souhaitez-vous faire autre chose ?';
    });

    final answer = await askWithRetry(
      speak: speak,
      listen: listen,
      question:
          'Souhaitez-vous faire autre chose ? Dites 1 pour oui, ou 2 pour non.',
      maxRetries: 2,
      shortAnswer: true,
      grammar: kYesNoGrammar,
    );

    if (answer == null) {
      await speak('Banque Parlante se met en veille. À bientôt.');
      await _closeSession(announce: false);
      return;
    }

    final parsed = parseYesNo(answer);
    if (parsed == false) {
      await speak('Très bien, au revoir et à bientôt sur Banque Parlante.');
      await _closeSession(announce: false);
      return;
    }

    if (parsed == true) {
      unawaited(_runVocalLoop(isWelcome: false));
      return;
    }

    // Si l'utilisateur a directement formulé une nouvelle commande
    final nextIntent = detectIntent(answer);
    if (nextIntent != BankIntent.none && nextIntent != BankIntent.quit) {
      unawaited(_startAction(nextIntent));
    } else if (nextIntent == BankIntent.quit) {
      await _closeSession(announce: true);
    } else {
      unawaited(_runVocalLoop(isWelcome: false));
    }
  }

  /// Boucle vocale interactive au premier plan : écoute et dialogue continus
  /// sans avoir besoin de toucher ou cliquer sur l'écran.
  Future<void> _runVocalLoop({required bool isWelcome}) async {
    if (_actionRunning || !mounted) return;
    final myId = ++_requestSeq;
    final token = CancelToken();
    _activeToken = token;

    final speak = _speakFor(token);
    final listen = _listenFor(token);

    try {
      if (isWelcome) {
        final recentBgSpeech =
            await OnboardingStorage.wasBackgroundSpeechRecent();
        if (!recentBgSpeech) {
          final name = await OnboardingStorage.getField('full_name');
          await TtsService.instance.speakWelcome(name: name);
        }
      }

      int silences = 0;
      while (mounted && myId == _requestSeq && !_actionRunning) {
        setState(() {
          _state = _ScreenState.action;
          _statusText = 'À votre écoute... Dites solde, virement, etc.';
        });

        ListenHint.shortAnswer = true;
        ListenHint.grammar = kMenuGrammar;

        String? heard;
        try {
          heard = await listen();
        } finally {
          ListenHint.shortAnswer = false;
          ListenHint.grammar = null;
        }

        if (myId != _requestSeq) return;

        if (heard != null && heard.trim().isNotEmpty) {
          silences = 0;
          final intent = detectIntent(heard);
          if (intent != BankIntent.none) {
            await _startAction(intent);
            return;
          } else {
            await speak(
              'Je n\'ai pas bien compris votre demande. Vous pouvez dire : '
              'solde, virement, historique, code de sécurité, profil, '
              'conseiller, ou quitter.',
            );
          }
        } else {
          silences++;
          if (silences == 1) {
            await speak(
              'Je vous écoute. Vous pouvez dire par exemple : solde, virement, historique, ou quitter.',
            );
          } else if (silences == 2) {
            await speak(
              'Êtes-vous toujours là ? Dites votre demande ou dites quitter.',
            );
          } else {
            await speak(
              'Aucune réponse entendue. Banque Parlante se met en veille. '
              'Dites "Banque Parlante" pour me réveiller.',
            );
            await _closeSession(announce: false);
            return;
          }
        }
      }
    } on FlowCancelled {
      // Interrompu par une touche physique ou autre commande
    } catch (_) {
    } finally {
      if (myId == _requestSeq && !_actionRunning && mounted) {
        setState(() {
          _state = _ScreenState.idle;
          _statusText = 'Mode 100% vocal actif. Dites votre demande.';
        });
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

    // Reste sur l'écran d'accueil en veille au lieu de quitter l'application
    if (mounted) {
      setState(() {
        _state = _ScreenState.idle;
        _activeIntent = BankIntent.none;
        _statusText = 'BanqueParle est en veille. Dites "Banque Parlante" ou touchez le micro pour commencer.';
      });
    }
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
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.blueFaint(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.blue, width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.record_voice_over, color: AppColors.blue, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '100% Vocal : aucun clic requis',
                      style: TextStyle(
                        color: AppColors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (_state == _ScreenState.idle) {
                    _checkPendingSteps(isColdStart: true);
                  }
                },
                borderRadius: BorderRadius.circular(50),
                child: _MicIndicator(active: busy),
              ),
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
                    'Le pavé numérique sera disponible après l\'enrôlement.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.blue, fontSize: 13),
                  ),
                ),
              _DiagnosticBox(
                lines: [
                  if (_voiceStatus.isNotEmpty) _voiceStatus,
                  if (_lastHeard.isNotEmpty) 'Entendu : $_lastHeard',
                  if (_lastDbError.isNotEmpty) 'Base : $_lastDbError',
                ],
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
                  'Écoute active en arrière-plan',
                  style: TextStyle(color: AppColors.blue, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    kNativeChannel.invokeMethod('openFullScreenIntentSettings'),
                child: const Text(
                  'Autoriser l\'ouverture automatique (réglages système)',
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

/// Bloc de diagnostic unique et discret : etat du moteur vocal, derniere
/// phrase entendue, derniere erreur de base. Il n'apparait que s'il y a
/// quelque chose a dire. Reserve au reglage ; l'application se pilote
/// entierement a la voix.
class _DiagnosticBox extends StatelessWidget {
  final List<String> lines;
  const _DiagnosticBox({required this.lines});

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.blueFaint(0.4), width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diagnostic',
            style: TextStyle(
              color: AppColors.blueFaint(0.7),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                line,
                style: const TextStyle(color: AppColors.blue, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
