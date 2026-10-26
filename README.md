# BanqueParle

Application bancaire mobile pilotée par la voix, conçue pour les personnes
malvoyantes. Elle écoute en permanence le mot-clé « Banque Parlante »,
enrôle le client à la voix (identité, compte, sécurité) et permet de
consulter son solde, son historique, de faire des virements instantanés
entre comptes, d'obtenir un code à usage unique, de gérer son profil et
d'appeler un conseiller.

## Sommaire

1. Téléchargement
2. Configuration unique du téléphone
3. Utilisation à la voix
4. Moteur de reconnaissance vocale
5. Base de données Neon
6. Secrets GitHub
7. Sécurité
8. Compatibilité et limites connues
9. Structure du dépôt
10. Charte graphique

---

## 1. Téléchargement

À chaque push sur la branche `main`, GitHub Actions construit l'APK, le
renomme `banqueparle.apk`, supprime l'ancienne version et publie la nouvelle
sous une adresse qui ne change jamais :

    https://github.com/<utilisateur>/<dépôt>/releases/download/latest/banqueparle.apk

Ce lien fonctionne sans compte GitHub et pointe toujours vers la dernière
version. Il est aussi affiché dans le résumé de chaque exécution du workflow
(onglet Actions).

L'APK est volumineux (environ 100 Mo) : il embarque le modèle de
reconnaissance vocale hors ligne (section 4). Le téléchargement se fait une
seule fois ; ensuite, la reconnaissance vocale n'a pas besoin d'internet.

---

## 2. Configuration unique du téléphone

Android restreint par défaut ce dont l'application a besoin : écouter en
permanence et s'ouvrir toute seule. Sans les réglages ci-dessous, le
téléphone répond à la voix mais l'écran ne s'allume pas, ou l'écoute
s'arrête après quelques minutes. Ce ne sont pas des défauts de
l'application, mais des protections du système que seul l'utilisateur peut
lever.

**Cette configuration se fait une seule fois, de préférence avec l'aide
d'une personne voyante. Ensuite, tout se fait à la voix.**

### Étape A - Premier lancement

1. Ouvrir BanqueParle (icône).
2. Accepter les autorisations demandées : Microphone, Notifications,
   Téléphone, et « Ne pas optimiser la batterie ».
3. **Attendre environ 30 secondes** au premier lancement : l'application
   prépare le modèle de reconnaissance vocale. L'écran indique « Moteur
   vocal : Vosk hors ligne actif » quand c'est prêt.

### Étape B - Autoriser l'ouverture automatique de l'écran

Depuis Android 14, une notification ne peut plus ouvrir une application
toute seule sans autorisation explicite. Dans l'application, appuyer sur
« Autoriser l'ouverture automatique (réglages système) », puis activer
l'interrupteur en face de BanqueParle.

Chemin manuel : Paramètres > Applications > BanqueParle > Notifications >
« Notifications plein écran ». Selon la marque, l'option peut aussi se
trouver dans Paramètres > Applications > Accès spécial.

Android 13 et antérieur : aucun réglage nécessaire pour cette étape.

### Étape C - Fonctionnement en arrière-plan, selon la marque

Chaque constructeur ajoute un gestionnaire d'énergie qui arrête les
applications en arrière-plan. Les libellés varient un peu selon la version.

**Samsung (One UI)** : Paramètres > Applications > BanqueParle > Batterie >
« Sans restriction ». Paramètres > Batterie > Limites d'utilisation en
arrière-plan > Applications jamais en veille : ajouter BanqueParle.

**Xiaomi, Redmi, POCO (MIUI, HyperOS)** : Paramètres > Applications > Gérer
les applications > BanqueParle > Démarrage automatique : activer ; puis
Économiser la batterie > « Aucune restriction ». Autorisations > Autres
autorisations : « Afficher sur l'écran de verrouillage » et « Afficher les
fenêtres contextuelles en arrière-plan ». Dans les applications récentes,
verrouiller BanqueParle (appui long sur la vignette, puis cadenas).

**Huawei, Honor (EMUI, MagicOS)** : Paramètres > Batterie > Lancement
d'applications > BanqueParle > désactiver la gestion automatique, puis
activer « Lancement automatique », « Lancement secondaire » et « Exécuter en
arrière-plan ».

**Oppo, Realme, OnePlus (ColorOS, OxygenOS)** : Paramètres > Applications >
Gestion des applications > BanqueParle > Utilisation de la batterie >
« Autoriser l'activité en arrière-plan » et « Autoriser le lancement
automatique ». Paramètres > Batterie : désactiver « Optimiser en veille ».

**Vivo, iQOO (Funtouch OS, OriginOS)** : Paramètres > Batterie >
Consommation en arrière-plan > BanqueParle > « Autoriser ». Paramètres >
Applications > Démarrage automatique : activer BanqueParle.

**Google Pixel, Motorola, Nokia (Android pur)** : Paramètres > Applications >
BanqueParle > Batterie > « Sans restriction ».

**Tecno, Infinix, Itel (HiOS, XOS)** : Gestionnaire du téléphone > Gestion de
l'énergie ou Démarrage automatique : autoriser BanqueParle. Paramètres >
Batterie > Optimisation : « Ne pas optimiser » pour BanqueParle.

### Étape D - Après un redémarrage du téléphone

Depuis Android 15, le système interdit de relancer automatiquement au
démarrage un service qui utilise le microphone. Après chaque redémarrage,
ouvrir BanqueParle une fois : l'écoute reprend et ne s'arrête plus tant que
le téléphone reste allumé.

### Si l'écran ne s'allume toujours pas

La réponse vocale fonctionne même dans ce cas : l'application parle sans
avoir besoin de l'écran. L'écran n'est indispensable que pour l'empreinte
digitale (Android n'affiche l'invite biométrique que sur un écran visible),
donc pour le solde, l'historique, le virement et le code à usage unique.
Le profil, le conseiller et l'arrêt ne l'exigent pas. Vérifier alors, dans
l'ordre : étape B, étape C, puis Paramètres > Applications > BanqueParle >
Autorisations > Microphone sur « Autoriser tout le temps » si l'option existe.

---

## 3. Utilisation à la voix

Dire « Banque Parlante », puis la demande, dans la même phrase ou après la
question « Que souhaitez-vous faire ? ». Exemples : « Banque Parlante
solde », « Banque Parlante trois ». L'application annonce ce qu'elle a
compris (« D'accord : consulter le solde ») avant d'agir.

Le pavé numérique affiché à l'écran offre les mêmes commandes par touche.
Un appui interrompt aussitôt la voix, l'écoute et l'invite d'empreinte en
cours, puis lance la nouvelle commande.

| Touche | Commande               | Mots reconnus                      | Sécurité exigée        |
|--------|------------------------|------------------------------------|------------------------|
| 1      | Consulter le solde     | solde                              | Biométrie              |
| 2      | Historique             | historique                         | Biométrie              |
| 3      | Effectuer un virement  | virement, transfert                | Biométrie forte        |
| 4      | Code OTP               | code, code de sécurité             | Biométrie              |
| 5      | Gestion du profil      | profil                             | Optionnelle            |
| 6      | Contacter un conseiller| conseiller                         | Aucune                 |
| 0      | Arrêter                | stop, arrête, zéro                 | Confirmation 1 ou 2    |

1. **Solde** : identité vérifiée, puis lecture du solde avec les centimes.
2. **Historique** : les trois dernières opérations, de la plus récente à la
   plus ancienne : sens, montant, nom du correspondant, quatre derniers
   chiffres de son compte, date. Un prélèvement est un débit : il apparaît
   comme un virement envoyé.
3. **Virement** : numéro du destinataire et montant dictés puis confirmés
   oralement, empreinte ET code secret, virement instantané, annonce du
   nouveau solde. Les montants avec centimes sont compris (« 12,50 »).
4. **Code OTP** : code de six chiffres généré par la base de données,
   valable cinq minutes, à usage unique, dicté chiffre par chiffre et
   répétable. Cinq codes maximum par période de dix minutes.
5. **Profil** : lecture du nom, de la date de naissance, du téléphone, de la
   fin du numéro de compte, du type de compte, des empreintes et de l'état du
   code secret ; modification du nom, du téléphone, de la date de naissance
   et du code secret (l'ancien code est exigé).
6. **Conseiller** : appel direct du centre de relation client (numéro fourni
   à la compilation, section 6). Si la permission d'appel est accordée,
   l'appel part seul ; sinon le numéro est prénuméroté dans le composeur.

### Arrêt d'urgence

À tout moment, « Banque Parlante arrête », « Banque Parlante stop », « stop »,
« arrête », « 0 » ou « zéro » (ou la touche 0 de l'écran) coupent l'activité en
cours, puis l'application demande : « Vous êtes sûr de vouloir arrêter Banque
Parlante ? Dites 1 pour oui, ou 2 pour non. »

- **Oui** : « Banque Parlante est arrêté », l'application se ferme en
  arrière-plan. L'écoute du mot-clé continue : dire « Banque Parlante » la
  relance.
- **Non** : « D'accord, on reprend », et l'activité repart du début de son
  parcours.
- **Sans réponse claire après trois essais** : l'arrêt est exécuté. Il a été
  demandé, et il peut s'agir d'une urgence.

« Zéro » est un chiffre légitime dans un code PIN ou un numéro de compte :
l'arrêt n'est déclenché que si toute la réponse est une commande d'arrêt. Un
code dicté « 0 0 0 0 » ne déclenche rien.

Limite : la commande vocale est entendue quand l'application écoute, donc
après chaque question. Pendant qu'elle parle, le micro est fermé (sinon elle
s'entendrait elle-même). Pour couper immédiatement une longue annonce,
utiliser la touche 0 de l'écran.

### Enrôlement (premier usage)

Questions posées une à une, avec confirmation orale des réponses sensibles et
relance si le silence dure dix secondes :

- Identité : nom complet, date de naissance, numéro de téléphone.
- Compte : numéro de compte, type de compte.
- Sécurité : empreinte digitale (jusqu'à trois), puis code secret à quatre
  chiffres obligatoire.

Chaque réponse est enregistrée aussitôt : si l'enrôlement est interrompu,
redire le mot-clé reprend à la question suivante. L'adresse e-mail n'est pas
demandée par la voix : dicter une adresse (arobase, points) est trop peu
fiable pour un canal de sécurité.

---

## 4. Moteur de reconnaissance vocale

### Pourquoi deux moteurs

- **Vosk (hors ligne)** pour tout ce qui a un vocabulaire connu : le
  mot-clé, oui/non, le menu. Le moteur n'écoute que ces mots et choisit
  parmi quelques candidats au lieu de deviner n'importe quelle phrase : il
  tolère donc beaucoup mieux l'accent, et il fonctionne sans internet.
- **Google** (repli) pour le texte libre : nom, date de naissance, montant,
  numéros. Ce moteur exige internet et est entraîné sur des accents
  standards.

Si Vosk n'est pas disponible (modèle pas encore préparé, erreur), tout
retombe automatiquement sur Google, comme avant. L'écran affiche l'état du
moteur et, en petit, « Dernière phrase entendue » : le texte exact reconnu,
précieux pour diagnostiquer un téléphone donné.

### Détails techniques

- Modèle : `vosk-model-small-fr-0.22` (41 Mo, licence Apache 2.0), téléchargé
  par le workflow à chaque build et intégré à l'APK. Il est extrait au premier
  lancement dans le stockage de l'application.
- Un seul modèle est chargé, dans le service d'arrière-plan, qui possède le
  micro. L'écran lui délègue ses écoutes par messages. Mémoire : prévoir
  environ 300 Mo de RAM disponibles.
- Le vocabulaire (`lib/services/grammars.dart`) contient toujours `[unk]` :
  sans lui, le moteur reste bloqué dès qu'un son sort de la grammaire.
- En mode grammaire, Vosk reconnaît parfois les mots sans jamais émettre de
  résultat final. Un résultat partiel qui reste stable 0,8 seconde est donc
  accepté.
- Le build utilise `--no-shrink` (le moteur n'est pas compatible avec la
  réduction de code R8) et cible les téléphones ARM, ce qui évite de
  multiplier la taille de l'APK par les bibliothèques x86.

### Disjoncteur anti-plantage

Un plantage natif (mémoire, bibliothèque, micro) ne peut pas être intercepté
par le code de l'application. Pour éviter qu'il se répète à chaque ouverture,
l'application note chaque étape risquée de Vosk (extraction du modèle,
chargement, ouverture du micro) et l'efface une fois terminée. Si le
téléphone a arrêté l'application pendant une étape, la version suivante
désactive Vosk, retombe sur Google et affiche à l'écran : « Vosk désactivé :
le téléphone a arrêté l'application pendant « étape » ». Cette information
sert à corriger le problème. Une nouvelle version de l'application retente
Vosk une fois.

Le modèle est extrait en flux (faible consommation de mémoire), quelques
secondes après l'affichage de l'écran.

### Reconnaissance des noms

Un nom comme « Houndokinnou Diègue » n'existe dans aucun dictionnaire : le
moteur libre propose le mot le plus proche (« Don Diègue »). La confirmation
orale permet de refuser, mais pas d'obtenir l'orthographe exacte. Piste
retenue : faire saisir le nom exact par la personne qui aide à la
configuration unique.

---

## 5. Base de données Neon

Les comptes et les virements sont stockés dans une base PostgreSQL hébergée
sur Neon. Aucun serveur applicatif n'est déployé : l'application se connecte
directement à Neon.

### Pourquoi c'est sûr malgré l'absence de serveur

Un identifiant partagé intégré à l'application permettrait à quiconque
décompile l'APK de lire ou modifier les soldes de tous les clients. Pour
l'éviter, toute la logique sensible vit dans la base (`sql/schema.sql`), sous
forme de fonctions `SECURITY DEFINER` :

- Chaque client possède son propre rôle PostgreSQL, créé à l'enrôlement, avec
  un mot de passe aléatoire conservé uniquement dans le stockage chiffré du
  téléphone.
- Ce rôle n'a aucun droit direct sur les tables : il ne peut qu'exécuter
  `transfer_funds()`, `get_balance()`, `get_history()`, `generate_otp()` et
  `update_owner_name()`.
- Ces fonctions déterminent elles-mêmes le compte émetteur à partir du rôle
  connecté (`session_user`) : un rôle compromis ne peut déplacer que l'argent
  de son propre compte.
- Le virement est une transaction atomique avec verrouillage des deux comptes
  dans un ordre fixe : pas de double dépense, pas de blocage mutuel.
- Le destinataire est crédité immédiatement.

Le seul identifiant présent dans l'APK est celui du rôle
`banqueparle_provisioner`, qui ne peut que créer un rôle client. Il ne peut
lire aucun solde.

### Mise en place (une seule fois)

GitHub n'exécute rien dans la base : c'est une étape manuelle. Tant que le
script n'est pas exécuté, le rôle `banqueparle_provisioner` n'existe pas et
l'application ne peut pas se connecter.

**Étape 1 - Exécuter le script SQL.** Console Neon > projet > branche
`production` > éditeur SQL (dans « Base de données Postgres »). Vérifier en
haut : base `neondb`, rôle `neondb_owner`. Ouvrir `sql/schema.sql` dans
GitHub (bouton « Raw »), tout copier, coller dans l'éditeur, cliquer sur
Run. Le script est rejouable : il peut être exécuté de nouveau en entier
après une mise à jour du fichier. Il faut le rejouer si une ancienne
version a été exécutée : elle contenait un défaut (`current_user` au lieu de
`session_user`) qui faisait échouer tout virement et toute lecture de solde.

**Étape 2 - Définir le mot de passe du rôle de provisionnement**, dans le
même éditeur (mot de passe long, aléatoire, sans apostrophe) :

    ALTER ROLE banqueparle_provisioner PASSWORD 'un-mot-de-passe-long-et-aléatoire';

**Étape 3 - Vérifier l'installation** :

    SELECT rolname FROM pg_roles
    WHERE rolname IN ('customer_base', 'banqueparle_provisioner', 'banqueparle_otp_verifier');

    SELECT proname FROM pg_proc
    WHERE proname IN ('create_customer_role', 'transfer_funds', 'get_balance',
                      'get_history', 'generate_otp', 'verify_otp', 'update_owner_name');

La première requête doit renvoyer 3 lignes, la seconde 7.

**Étape 4 - Renseigner les secrets GitHub** (section 6). Le rôle à mettre dans
`NEON_PROVISIONER_USER` est `banqueparle_provisioner`. Ne jamais y mettre
`neondb_owner` ni le mot de passe affiché dans la fenêtre « Connecter » de
Neon : ce sont ceux du propriétaire de la base, et tout ce que contient
l'APK peut être extrait par quiconque le télécharge. Le workflow refuse de
construire l'APK si le rôle ressemble à un rôle administrateur.

Pour `NEON_HOST`, utiliser l'hôte **direct** : dans la fenêtre « Connecter »,
désactiver « Mise en commun des connexions », puis copier uniquement le nom
d'hôte, par exemple `ep-nom-123456.us-east-2.aws.neon.tech`, sans
`postgresql://`, sans identifiants, sans port.

**Étape 5 - Reconstruire l'APK.** Les secrets sont intégrés à la compilation :
après toute modification, relancer le workflow, puis réinstaller l'APK.

### Tester un virement

Un compte neuf démarre à zéro. Pour tester, créditer un compte depuis
l'éditeur SQL :

    UPDATE accounts SET balance = 50000 WHERE account_number = '123456';

Enrôler ensuite un second compte, puis dire « Banque Parlante virement ».

### En cas d'erreur de base de données

L'application dit la cause et affiche en petit « Dernière erreur base ».

| Message de l'application                  | Cause                                | Solution |
|-------------------------------------------|--------------------------------------|----------|
| base de données introuvable               | Nom de base incorrect                | Définir `NEON_DATABASE` (défaut `neondb`), reconstruire |
| script SQL non installé                   | `schema.sql` non exécuté             | Étape 1 |
| identifiants refusés                      | Rôle absent ou mot de passe différent| Étapes 1 et 2, secrets identiques, reconstruire |
| droits insuffisants                       | Ancienne version du script           | Rejouer `schema.sql` |
| adresse du serveur introuvable            | `NEON_HOST` faux, ou pas d'internet  | Nom d'hôte seul |
| impossible de joindre la banque           | Pas de connexion internet            | Vérifier le réseau |

### Limites

- Le numéro de compte est déclaré par l'utilisateur à l'enrôlement. Un
  numéro déjà enregistré est refusé, mais rien ne prouve qu'un numéro libre
  appartient à la personne. Pour un déploiement réel, la banque doit
  pré-créer les comptes et remettre un code d'activation.
- Si le réseau tombe entre la création du rôle côté Neon et la réception du
  mot de passe par le téléphone, le compte existe côté base mais l'application
  ne peut plus s'y connecter. Il faut supprimer la ligne dans `accounts` et le
  rôle `cust_<numéro>`, puis refaire l'enrôlement.
- Un virement dont la réponse se perd est annoncé comme échoué alors qu'il
  peut avoir abouti. Avant de le refaire, vérifier l'historique (touche 2).
- Les virements exigent internet.

---

## 6. Secrets GitHub

Settings > Secrets and variables > Actions :

| Secret                      | Valeur                                                  |
|-----------------------------|---------------------------------------------------------|
| NEON_HOST                   | Nom d'hôte direct Neon (sans `-pooler`)                 |
| NEON_DATABASE               | Nom de la base (facultatif, défaut `neondb`)            |
| NEON_PROVISIONER_USER       | `banqueparle_provisioner`                               |
| NEON_PROVISIONER_PASSWORD   | Mot de passe défini à l'étape 2                         |
| ADVISOR_PHONE               | Numéro du centre de relation client, format international (secret ou variable) |

Sans ces secrets, l'APK se construit quand même, mais les virements sont
désactivés et l'application l'annonce à l'oral.

---

## 7. Sécurité

- **Biométrie** : empreinte (3 essais) ; si le téléphone n'a pas de lecteur
  ou si l'empreinte échoue, repli sur le code secret.
- **Biométrie forte** (virement) : empreinte ET code secret, sans repli.
  Le cahier des charges ne définit pas « forte » ; cette interprétation
  (deux facteurs) est la plus défendable pour une opération qui déplace de
  l'argent.
- **Confirmation d'un virement** : seuls « oui », « 1 » et « un » valent
  accord. Une réponse non comprise ou ambiguë est redemandée ; sans réponse
  claire après trois essais, le virement est annulé.
- L'application ne conserve aucun état authentifié : chaque opération
  sensible redemande l'identité.
- Aucune application tierce ne peut enrôler un nouveau doigt : cette
  opération est réservée aux réglages du téléphone. L'application authentifie
  avec les empreintes déjà enregistrées ; sinon, elle passe au code secret.

---

## 8. Compatibilité et limites connues

- Android 6.0 (API 23) et supérieur, téléphones ARM.
- Mémoire : prévoir environ 300 Mo de RAM libres pour le moteur vocal. Sur un
  téléphone très limité, le système peut arrêter le service d'écoute.
- Le moteur de repli (Google) exige un service de reconnaissance vocale
  installé. Les téléphones sans services Google n'en ont pas ; Vosk, lui,
  fonctionne sans.
- L'authentification biométrique n'est possible que sur un écran affiché :
  l'ouverture de l'application est requise pour les touches 1 à 4.
- Le code secret à quatre chiffres n'a que dix mille combinaisons. Il est
  stocké haché, mais une personne ayant accès aux fichiers d'un téléphone
  déverrouillé (root) pourrait le retrouver. C'est un facteur de repli.
- Le code OTP est dicté à voix haute : il est audible par les personnes
  proches. C'est inhérent au fonctionnement vocal demandé.
- Certains téléphones émettent un court bip système lors de l'écoute avec le
  moteur de repli. Vosk n'en émet pas.

---

## 9. Structure du dépôt

    .github/workflows/build-apk.yml       Construction et publication de l'APK
    android_overrides/                    Fichiers Android appliqués par la CI
    sql/schema.sql                        Schéma et fonctions Neon
    assets/models/                        Modèle vocal (téléchargé par la CI)
    lib/
      main.dart
      screens/home_screen.dart
      services/
        wake_word_service.dart            Mot-clé et conversation en arrière-plan
        vosk_engine.dart                  Moteur hors ligne, repli, délégation
        grammars.dart                     Vocabulaires restreints
        stop_command.dart                 Arrêt d'urgence
        command_intent.dart               Reconnaissance des commandes
        voice_dialog.dart, stt_helper.dart, tts_service.dart
        auth_gate.dart                    Biométrie simple ou forte
        balance_flow.dart ... advisor_flow.dart   Touches 1 à 6
        transfer_service.dart             Accès Neon
      utils/                              Couleurs, stockage, analyse de montants...

Les dossiers `android/`, `ios/` et `build/` ne sont pas versionnés : la CI les
régénère à chaque build puis applique `android_overrides/`.

---

## 10. Charte graphique

Deux couleurs uniquement, sans exception :

| Usage         | Couleur | Code      |
|---------------|---------|-----------|
| Accent, texte | Bleu    | `#1A73E8` |
| Fond          | Blanc   | `#FFFFFF` |
