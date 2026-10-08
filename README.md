# BanqueParle

Application bancaire mobile Flutter pilotee par la voix, concue pour
l'accessibilite. Elle detecte en permanence le mot-cle "Banque
Parlante", enrole le client a la voix (identite, compte, securite) et
permet d'effectuer des virements instantanes entre comptes.

## Sommaire

1. Telechargement de l'application
2. Premiere utilisation et configuration du telephone
3. Base de donnees Neon et securite des virements
4. Configuration du depot GitHub (secrets)
5. Fonctionnalites
6. Compatibilite et limites connues
7. Structure du depot
8. Charte graphique

---

## 1. Telechargement de l'application

A chaque push sur la branche `main`, GitHub Actions construit l'APK,
le renomme `banqueparle.apk`, supprime l'ancienne version et publie la
nouvelle sous une adresse qui ne change jamais :

    https://github.com/<utilisateur>/<depot>/releases/download/latest/banqueparle.apk

Remplacer `<utilisateur>` et `<depot>` par ceux du depot. Ce lien
fonctionne sans compte GitHub et pointe toujours vers la derniere
version. Il n'existe jamais qu'une seule version publiee. Le lien est
aussi affiche dans le resume de chaque execution du workflow (onglet
Actions).

Installation : ouvrir le lien sur le telephone, telecharger le fichier,
l'ouvrir, et autoriser l'installation depuis cette source si Android le
demande.

---

## 2. Premiere utilisation et configuration du telephone

L'application doit pouvoir tourner en arriere-plan en permanence pour
entendre le mot-cle, et s'ouvrir seule a l'ecran quand elle l'entend.
Android restreint les deux par defaut. Sans les reglages ci-dessous, le
telephone repond a la voix mais l'ecran ne s'allume pas, ou l'ecoute
s'arrete apres quelques minutes. Ce n'est pas un defaut de
l'application : ce sont des protections du systeme que seul
l'utilisateur peut lever, une fois.

### Etape A - Permissions demandees au premier lancement

Accepter : Microphone, Notifications, et "Ne pas optimiser la batterie"
pour BanqueParle.

### Etape B - Autoriser l'ouverture automatique de l'ecran

Depuis Android 14, une notification n'a plus le droit d'ouvrir une
application toute seule, sauf autorisation explicite.

Methode rapide :
1. Ouvrir BanqueParle (icone).
2. Appuyer sur "Autoriser l'ouverture automatique (reglages systeme)".
3. Activer l'interrupteur en face de BanqueParle.

Methode manuelle : Parametres > Applications > BanqueParle >
Notifications > "Notifications plein ecran" (ou "Autoriser les
notifications plein ecran"). Selon la marque, l'option peut aussi se
trouver dans Parametres > Applications > Acces speciaux des
applications > Notifications plein ecran.

Android 13 et anterieur : aucun reglage necessaire pour cette etape.

### Etape C - Autoriser le fonctionnement en arriere-plan (selon la marque)

Chaque constructeur ajoute son propre gestionnaire d'energie qui tue
les applications en arriere-plan. Les libelles varient un peu selon la
version ; chercher l'option equivalente.

Samsung (One UI)
- Parametres > Applications > BanqueParle > Batterie > "Sans
  restriction".
- Parametres > Batterie > Limites d'utilisation en arriere-plan >
  Applications jamais en veille : ajouter BanqueParle.
- Retirer BanqueParle de "Applications en veille prolongee" si present.

Xiaomi, Redmi, POCO (MIUI / HyperOS)
- Parametres > Applications > Gerer les applications > BanqueParle >
  Demarrage automatique : activer.
- Meme ecran > Economiser la batterie > "Aucune restriction".
- Parametres > Applications > Autorisations > Autres autorisations >
  "Afficher sur ecran de verrouillage" et "Afficher les fenetres
  contextuelles en arriere-plan" : autoriser.
- Dans la liste des applications recentes, verrouiller BanqueParle
  (appui long sur la vignette, puis icone de cadenas).

Huawei, Honor (EMUI / MagicOS)
- Parametres > Batterie > Lancement d'applications > BanqueParle >
  desactiver la gestion automatique, puis activer "Lancement
  automatique", "Lancement secondaire" et "Executer en arriere-plan".
- Appareils recents sans services Google : voir la section 6.

Oppo, Realme, OnePlus (ColorOS / OxygenOS)
- Parametres > Applications > Gestion des applications > BanqueParle >
  Utilisation de la batterie > "Autoriser l'activite en arriere-plan"
  et "Autoriser le lancement automatique".
- Parametres > Batterie > Plus de parametres > desactiver
  "Optimiser en veille".

Vivo, iQOO (Funtouch OS / OriginOS)
- Parametres > Batterie > Consommation en arriere-plan > BanqueParle >
  "Autoriser".
- Parametres > Applications > Demarrage automatique : activer
  BanqueParle.

Google Pixel, Motorola, Nokia, Android One (Android pur)
- Parametres > Applications > BanqueParle > Batterie > "Sans
  restriction". Aucun reglage constructeur supplementaire.

Tecno, Infinix, Itel (HiOS / XOS)
- Gestionnaire du telephone (Phone Master) > Gestion de l'energie ou
  Demarrage automatique : autoriser BanqueParle.
- Parametres > Batterie > Optimisation de la batterie : BanqueParle sur
  "Ne pas optimiser".

### Etape D - Apres un redemarrage du telephone

Depuis Android 15, le systeme interdit de relancer automatiquement au
demarrage un service qui utilise le microphone. Apres chaque
redemarrage, ouvrir BanqueParle une fois : l'ecoute reprend et ne
s'arrete plus tant que le telephone reste allume.

### Si l'ecran ne s'allume toujours pas

La reponse vocale fonctionne meme dans ce cas : l'application parle
sans avoir besoin de l'ecran. L'ecran n'est indispensable que pour
l'etape de l'empreinte digitale (Android n'affiche l'invite biometrique
que sur un ecran visible), donc pour toutes les fonctions protegees par
l'empreinte : solde, historique, virement et code OTP. Le profil, le
conseiller et "quitter" ne l'exigent pas. Verifier alors, dans l'ordre : etape B, etape C, puis
Parametres > Applications > BanqueParle > Autorisations > Microphone sur
"Autoriser tout le temps" si l'option existe.

---

## 3. Base de donnees Neon et securite des virements

Les comptes et les virements sont stockes dans une base PostgreSQL
hebergee sur Neon. Aucun serveur applicatif n'est deploye : l'application
se connecte directement a Neon.

### Pourquoi c'est sur malgre l'absence de serveur

Une application qui se connecterait avec un identifiant partage
permettrait a quiconque decompile l'APK de lire ou modifier les soldes
de tous les clients. Pour l'eviter, toute la logique sensible est
dans la base elle-meme (`sql/schema.sql`), sous forme de fonctions
`SECURITY DEFINER` :

- Chaque client possede son propre role PostgreSQL, cree
  automatiquement a l'enrolement, avec un mot de passe aleatoire
  conserve uniquement dans le stockage chiffre du telephone.
- Ce role n'a aucun droit direct de lecture ou d'ecriture sur les
  tables. Il ne peut qu'executer `transfer_funds()` et `get_balance()`.
- `transfer_funds()` determine elle-meme le compte emetteur a partir du
  role connecte : un role compromis ne peut deplacer que l'argent de
  son propre compte, jamais celui d'un autre.
- Le virement est une transaction atomique avec verrouillage des deux
  comptes : pas de double depense, pas de debit sans credit.
- Le credit du destinataire est immediat : des que la transaction est
  validee, le destinataire voit son nouveau solde.
- Avant chaque virement, l'application redemande l'empreinte digitale
  (ou le code secret en repli).

Le seul identifiant present dans l'APK est celui du role
`banqueparle_provisioner`, qui peut uniquement appeler
`create_customer_role()`. Il ne peut lire aucun solde.

### Mise en place (une seule fois)

1. Creer un projet Neon et une base nommee `banqueparle`.
2. Dans l'editeur SQL de Neon, connecte avec le role proprietaire
   (par defaut `neondb_owner`), executer le contenu de
   `sql/schema.sql`.
   Si une version precedente du script a deja ete executee, le
   rejouer en entier : il est idempotent, et il corrige un defaut
   des versions anterieures (les fonctions identifiaient l'appelant
   avec `current_user`, qui designe le proprietaire de la fonction et non
   le client connecte ; elles utilisent maintenant `session_user`). Sans
   cette correction, tout virement ou toute lecture de solde echoue.
3. Definir le mot de passe du role de provisionnement :

       ALTER ROLE banqueparle_provisioner PASSWORD 'un-mot-de-passe-long-et-aleatoire';

4. Relever l'hote de connexion directe (sans `-pooler`) dans le
   tableau de bord Neon, par exemple
   `ep-nom-123456.eu-central-1.aws.neon.tech`.
5. Renseigner les secrets GitHub (section 4).

### Tester un virement

Un compte cree a l'enrolement demarre avec un solde de zero. Pour
tester, crediter un compte depuis l'editeur SQL de Neon :

    UPDATE accounts SET balance = 50000 WHERE account_number = '123456';

Enroler ensuite un second telephone (ou un second compte), puis dire
"Banque Parlante" et "effectuer un virement".

### Limites a connaitre

- Le numero de compte est declare par l'utilisateur a l'enrolement.
  Un numero deja enregistre est refuse, mais rien ne prouve qu'un
  numero libre appartient bien a la personne. Pour un deploiement
  reel, la banque doit pre-creer les comptes et remettre un code
  d'activation. Ce prototype ne le fait pas.
- Si le reseau tombe exactement entre la creation du role cote Neon et
  la reception du mot de passe par le telephone, le compte existe cote
  base mais l'application ne peut plus s'y connecter. Il faut alors
  supprimer la ligne correspondante dans `accounts` et le role
  `cust_<numero>` depuis la console Neon, puis refaire l'enrolement.
- Les virements exigent une connexion internet. Ils echouent
  proprement, avec un message vocal, sans rien debiter, si le reseau
  est absent.

---

## 4. Configuration du depot GitHub (secrets)

Les identifiants de la base ne doivent jamais etre dans le depot. Les
ajouter dans GitHub : Settings > Secrets and variables > Actions >
New repository secret.

| Secret                      | Valeur                                      |
|-----------------------------|---------------------------------------------|
| NEON_HOST                   | Hote direct Neon (sans -pooler)             |
| NEON_DATABASE               | Nom de la base (optionnel, defaut banqueparle) |
| NEON_PROVISIONER_USER       | `banqueparle_provisioner`                   |
| NEON_PROVISIONER_PASSWORD   | Mot de passe defini a l'etape 3             |
| ADVISOR_PHONE               | Numero du centre de relation client (touche 6), au format international, par exemple +22990000000. Accepte aussi comme variable (Settings > Secrets and variables > Actions > Variables) |

Sans ces secrets, l'APK se construit quand meme, mais l'application
annonce a l'oral que la base de donnees n'est pas configuree et les
virements sont desactives. Un avertissement apparait dans le journal du
workflow.

Ne pas utiliser le mot de passe du role proprietaire de la base : le
role de provisionnement a justement ete concu pour que l'APK ne
contienne jamais un identifiant capable de lire les donnees.

---

## 5. Fonctionnalites

Detection du mot-cle : service d'arriere-plan permanent, ecoute en
francais, tolerance aux homophones.

Enrolement vocal, une question a la fois, avec confirmation orale des
reponses sensibles et relance apres dix secondes de silence :
- Identite : nom complet, date de naissance, numero de telephone.
- Compte bancaire : numero de compte, type de compte.
- Securite : empreinte digitale (jusqu'a trois enregistrements) puis
  code secret a quatre chiffres obligatoire, stocke sous forme de
  hachage SHA-256.
- Activation du compte bancaire sur Neon.

Chaque reponse est enregistree immediatement : si l'enrolement est
interrompu, redire le mot-cle reprend a la question suivante.

### Les commandes (cahier des charges, section 3.1)

Apres l'enrolement, chaque fonction est accessible de deux manieres :
en disant "Banque Parlante" puis la demande (ou son numero), ou en
appuyant sur la touche du pave numerique affiche a l'ecran. Un appui
sur une touche interrompt immediatement la voix, l'ecoute et l'invite
d'empreinte en cours, puis lance la nouvelle commande.

| Touche | Commande               | Mots reconnus (exemples)                  | Securite exigee          |
|--------|------------------------|-------------------------------------------|--------------------------|
| 1      | Consulter le solde     | solde, combien                            | Biometrie                |
| 2      | Historique             | historique, operations, dernier virement  | Biometrie                |
| 3      | Effectuer un virement  | virement, transfert, envoyer              | Biometrie forte          |
| 4      | Code OTP               | code, OTP, code temporaire                | Biometrie                |
| 5      | Gestion du profil      | profil, modifier, parametres              | Optionnelle              |
| 6      | Contacter un conseiller| conseiller, appeler, contacter            | Aucune                   |
| 0      | Quitter                | quitter, fermer, au revoir                | Aucune                   |

Details de chaque fonction :

1. Solde : identite verifiee, puis lecture du solde avec les centimes
   lorsqu'il y en a.
2. Historique : les trois dernieres operations, de la plus recente a la
   plus ancienne, avec le sens (envoye ou recu), le montant, le nom du
   correspondant, les quatre derniers chiffres de son compte et la date.
   Le modele ne contient que des virements ; un prelevement est un debit
   et apparait comme un virement envoye.
3. Virement : numero du destinataire et montant dictes puis confirmes
   oralement, empreinte ET code secret exiges, virement instantane,
   annonce du nouveau solde. Les montants avec centimes sont compris
   ("12,50", "12 euros 50").
4. Code OTP : code de six chiffres genere par la base de donnees avec un
   generateur cryptographique, valable cinq minutes, a usage unique,
   dicte chiffre par chiffre et repetable. Cinq codes maximum par
   periode de dix minutes. Le systeme destinataire verifie le code avec
   la fonction `verify_otp` (voir sql/schema.sql).
5. Profil : lecture du nom, de la date de naissance, du telephone, de la
   fin du numero de compte, du type de compte, du nombre d'empreintes et
   de l'etat du code secret. Modification possible du nom, du telephone,
   de la date de naissance et du code secret. Changer le code secret
   exige de donner l'ancien. Le nom est synchronise avec la base ; le
   telephone et la date de naissance restent sur le telephone. Le numero
   de compte n'est pas modifiable.
6. Conseiller : appel direct du centre de relation client. Le numero est
   fourni a la compilation (section 4). Si la permission d'appel a ete
   accordee, l'appel part seul ; sinon le numero est pre-compose dans le
   composeur.
0. Quitter : coupe la voix, l'ecoute et toute invite en cours, ferme
   l'ecran et laisse le service d'ecoute actif en arriere-plan.
   L'application ne conserve aucun etat authentifie : chaque operation
   sensible redemande l'identite, il n'y a donc pas de session a
   invalider au-dela de cette fermeture.

"Biometrie forte" n'est pas defini precisement par le cahier des
charges. Il est interprete ici comme un double facteur : empreinte puis
code secret, sans repli. Pour les fonctions a "Biometrie" simple, le
code secret sert de repli si l'empreinte echoue ou si le telephone n'a
pas de lecteur.

Note d'ingenierie : l'adresse email n'est pas demandee par la voix. La
dictee d'une adresse (arobase, points) est trop peu fiable pour un
canal de securite.

### Application lancee plusieurs fois

Cause corrigee : l'activite principale utilisait un parametre
(`taskAffinity` vide) qui pouvait creer une fenetre independante a
chaque lancement. Elle est maintenant en `singleTask` : une seule
instance existe, quel que soit le declencheur (icone, notification,
mot-cle). En complement, un verrou empeche deux executions simultanees
du meme flux vocal, et le service d'arriere-plan s'efface (micro et
voix) pendant qu'un flux tourne au premier plan. Les valeurs partagees
entre le service et l'interface (deux isolats Dart distincts) sont
relues depuis le disque a chaque acces, pour qu'aucun des deux ne
travaille sur une donnee perimee.

---

## 6. Compatibilite et limites connues

- Android 6.0 (API 23) et superieur, soit la quasi-totalite des
  telephones actuellement utilises.
- La reconnaissance vocale s'appuie sur le service vocal du systeme.
  Les telephones sans services Google (certains Huawei et Honor
  recents, ROM alternatives) n'ont pas de moteur de reconnaissance
  installe : le mot-cle ne peut pas y etre detecte. Installer le
  service de reconnaissance vocale Google, avec la langue francaise
  telechargee pour un usage hors ligne, resout le probleme sur tous
  les appareils qui l'acceptent.
- Certains telephones emettent un court bip systeme a chaque
  redemarrage de l'ecoute. C'est un comportement du moteur vocal
  Android, non modifiable par l'application.
- Aucune application tierce ne peut enroler un nouveau doigt dans le
  capteur d'empreinte : cette operation est reservee aux reglages du
  telephone. L'application authentifie avec les empreintes deja
  enregistrees sur l'appareil. Si aucune n'est enregistree, elle passe
  directement au code secret.
- Le code secret a quatre chiffres n'a que dix mille combinaisons. Il
  est stocke sous forme de hachage, mais une personne ayant acces aux
  fichiers d'un telephone deverrouille (root) pourrait le retrouver.
  C'est un facteur de repli, pas une protection contre ce scenario.
- Un virement dont la reponse se perd (coupure reseau apres validation
  par la base) est annonce comme echoue alors qu'il peut avoir abouti.
  Avant de le refaire, consulter l'historique (touche 2) ou le solde
  (touche 1).
- Le code OTP est dicte a voix haute : il est audible par les personnes
  proches. C'est inherent au fonctionnement vocal demande.
- L'authentification biometrique n'est possible que sur un ecran
  affiche : c'est pourquoi l'ouverture de l'application est requise
  pour toute fonction protegee par l'empreinte (touches 1, 2, 3 et 4).

---

## 7. Structure du depot

    .github/workflows/build-apk.yml       Construction et publication de l'APK
    android_overrides/                    Fichiers Android appliques par la CI
      main/AndroidManifest.xml
      main/kotlin/MainActivity.kt
      test/widget_test.dart
    sql/schema.sql                        Schema et fonctions Neon
    lib/
      main.dart
      screens/home_screen.dart
      services/
        wake_word_service.dart            Mot-cle et conversation en arriere-plan
        command_intent.dart               Reconnaissance des commandes
        onboarding_fields.dart            Champs du formulaire
        fingerprint_enrollment_flow.dart
        pin_enrollment_flow.dart
        pin_verification.dart
        account_provisioning_service.dart Creation du role bancaire du client
        transfer_service.dart             Acces Neon : virement, solde, historique, OTP
        auth_gate.dart                    Biometrie simple ou forte
        flow_control.dart                 Annulation d'une commande en cours
        balance_flow.dart                 Touche 1
        history_flow.dart                 Touche 2
        transfer_flow.dart                Touche 3
        otp_flow.dart                     Touche 4
        profile_flow.dart                 Touche 5
        advisor_flow.dart                 Touche 6
        voice_dialog.dart, stt_helper.dart, tts_service.dart
      utils/
        app_colors.dart, onboarding_storage.dart, text_normalize.dart,
        digit_parser.dart, amount_parser.dart, native_channel.dart,
        permissions_helper.dart

Les dossiers `android/`, `ios/` et `build/` ne sont pas versionnes : la
CI les regenere a chaque build puis applique `android_overrides/`.

---

## 8. Charte graphique

Deux couleurs uniquement, sans exception :

| Usage          | Couleur | Code      |
|----------------|---------|-----------|
| Accent, texte  | Bleu    | `#1A73E8` |
| Fond           | Blanc   | `#FFFFFF` |
