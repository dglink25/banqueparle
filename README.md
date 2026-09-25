# BanqueParle — Fonctionnalités de base (Mot-clé vocal)

Application Flutter accessible, pilotée par la voix. Ce dépôt implémente les
**fonctionnalités de base** demandées :

1. 🎙️ **Détection permanente du mot-clé « Banque Parlante »**, y compris
   application fermée / téléphone verrouillé (service d'arrière-plan +
   notification "plein écran" qui réveille l'app comme un appel entrant).
2. 📲 **Ouverture automatique de l'application** dès que le mot-clé est
   reconnu.
3. 🔊 **Message de bienvenue vocal (TTS)** joué systématiquement à
   l'ouverture (manuelle ou déclenchée par la voix).
4. ⚙️ **Build automatique de l'APK sur GitHub Actions** à chaque `push`
   — aucun build local nécessaire.

---

## 📁 Structure du dépôt

```
banqueparle/
├── .github/workflows/build-apk.yml   # Pipeline CI : build APK automatique
├── android_overrides/main/AndroidManifest.xml  # Permissions & config Android
├── lib/
│   ├── main.dart                     # Point d'entrée
│   ├── services/
│   │   ├── wake_word_service.dart    # Écoute continue + détection mot-clé
│   │   └── tts_service.dart          # Synthèse vocale (message de bienvenue)
│   ├── screens/home_screen.dart      # Écran principal
│   └── utils/permissions_helper.dart # Gestion des permissions
├── pubspec.yaml
└── .gitignore
```

> ℹ️ Les dossiers `android/`, `ios/`, `build/` **ne sont pas committés**.
> Ils sont régénérés automatiquement à chaque exécution du workflow CI
> (`flutter create`), puis notre `AndroidManifest.xml` personnalisé est
> appliqué par-dessus. Cela évite de polluer le dépôt avec des fichiers
> binaires générés (gradle wrapper, etc.) et garantit un build toujours
> à jour avec la dernière version stable de Flutter.

---

## 🚀 Mise en route (aucun outil requis en local)

### 1. Créer le dépôt Git et pousser le code

```bash
cd banqueparle
git init
git add .
git commit -m "Initial commit — BanqueParle (mot-clé vocal + TTS + CI)"
git branch -M main
git remote add origin https://github.com/<votre-utilisateur>/banqueparle.git
git push -u origin main
```

### 2. Le build se lance automatiquement

Dès le `push`, l'onglet **Actions** de votre dépôt GitHub montre le workflow
`Build APK BanqueParle` s'exécuter. À la fin (~5-8 minutes) :

- L'**APK signé en mode release** est disponible dans l'onglet **Actions**
  → cliquez sur le run → section **Artifacts** → `banqueparle-apk-XX`.
- Si vous créez un **tag** (`git tag v1.0.0 && git push origin v1.0.0`),
  une **Release GitHub** est créée automatiquement avec l'APK attaché,
  prêt à télécharger et installer sur un téléphone Android.

### 3. Installer l'APK sur votre téléphone

Téléchargez `app-release.apk` depuis GitHub, transférez-le sur le
téléphone, puis installez-le (autoriser "Sources inconnues" si demandé).

Au premier lancement, l'application demande :
- la permission **Microphone** (obligatoire),
- la permission **Notifications** (obligatoire, pour réveiller l'app),
- de **désactiver l'optimisation de batterie** pour BanqueParle
  (fortement recommandé, sinon Android peut arrêter l'écoute après
  quelques minutes en arrière-plan).

Une fois ces permissions accordées : dites **« Banque Parlante »**, même
appli fermée ou téléphone verrouillé → l'application s'ouvre et énonce le
message de bienvenue.

---

## 🔊 Fonctionnement technique du mot-clé

Le module `wake_word_service.dart` :

- tourne en **Foreground Service Android** (notification persistante
  discrète, requis par Android pour garder le micro actif en tâche de fond) ;
- écoute en continu via `speech_to_text`, relance automatiquement
  l'écoute après chaque timeout/silence ;
- normalise et compare le texte reconnu à une liste de variantes
  phonétiques tolérées (« banque parlante », « banc parlant », etc.)
  pour gérer les homophones du français, comme demandé au cahier des
  charges ;
- à la détection, affiche une **notification "Full-Screen Intent"**
  (même mécanisme que les appels entrants ou les alarmes), qui réveille
  l'écran et ouvre l'application automatiquement.

## ⚠️ Notes importantes / limites connues

- **Reconnaissance vocale en ligne vs hors-ligne** : `speech_to_text`
  s'appuie sur le moteur de reconnaissance du système (Google
  Speech Services sur Android). Le cahier des charges v2 prévoit à
  terme un moteur 100% embarqué (Picovoise Porcupine / Vosk) pour
  fonctionner sans connexion — cette évolution nécessite l'entraînement
  d'un modèle de mot-clé personnalisé (`.ppn` / modèle Vosk fr) sur la
  console Picovoice, non générable automatiquement. La présente version
  livre une implémentation fonctionnelle équivalente, prête à être
  remplacée par ce moteur embarqué dans une itération suivante.
- Certains constructeurs (Xiaomi, Huawei, Samsung en mode économie
  d'énergie agressif) tuent les services d'arrière-plan malgré la
  permission accordée : il faut alors ajouter BanqueParle à la liste des
  "applications protégées"/"autoriser en arrière-plan" dans les
  réglages du téléphone.
- iOS ne permet pas d'écoute micro continue en arrière-plan pour des
  raisons de plateforme ; la configuration iOS fournie couvre le premier
  plan uniquement.

## 🔜 Prochaines fonctionnalités (hors périmètre de cette livraison)

Conformément au cahier des charges : consultation du solde, historique,
virement vocal, code OTP, gestion du profil, mise en relation conseiller,
authentification biométrique (`local_auth`), pavé numérique de secours.
