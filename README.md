# BanqueParle

Application bancaire mobile Flutter pilotee par la voix, concue pour
l'accessibilite. Ce depot contient l'implementation des fonctionnalites
de base : detection permanente du mot-cle vocal, enrolement complet du
client (identite, compte bancaire, securite), et integration continue
pour la production automatique de l'APK.

## Charte graphique

Deux couleurs uniquement dans toute l'application, sans exception :

| Usage             | Couleur | Code       |
|-------------------|---------|------------|
| Accent, texte      | Bleu    | `#1A73E8`  |
| Fond               | Blanc   | `#FFFFFF`  |

Aucune autre teinte n'est utilisee. Les variations d'intensite (ombres,
surfaces attenuees) derivent uniquement du bleu via une opacite reduite.

## Fonctionnalites livrees

1. Detection permanente du mot-cle "Banque Parlante", y compris
   application fermee ou telephone verrouille (service d'arriere-plan).
2. Reponse vocale immediate, generee directement par le service
   d'arriere-plan (independante de l'ouverture de l'interface).
3. Enrolement complet du client au premier usage, mene comme un
   veritable formulaire, une question a la fois, avec confirmation
   orale des reponses sensibles et relance automatique apres un silence
   de dix secondes.
4. Configuration de la securite du compte : empreinte digitale
   (jusqu'a trois enregistrements) puis code secret de secours a quatre
   chiffres, obligatoire, jamais stocke en clair.
5. Build automatique de l'APK a chaque push via GitHub Actions, sans
   build local necessaire.

## Champs collectes lors de l'enrolement

Le cahier des charges ne precisait pas la liste exacte des informations
a recueillir. Les champs suivants ont ete definis par ingenierie, sur la
base des pratiques standard d'ouverture de service bancaire, et figurent
dans `lib/services/onboarding_fields.dart` :

Section identite :
- Nom complet
- Date de naissance
- Numero de telephone

Section compte bancaire :
- Numero de compte bancaire
- Type de compte (courant ou epargne)

Section securite :
- Empreinte digitale (optionnelle, jusqu'a trois enregistrements)
- Code secret de secours a quatre chiffres (obligatoire)

Note d'ingenierie : l'adresse email n'est volontairement pas demandee
par la voix. La dictee vocale d'une adresse email (caracteres speciaux,
point, arobase) est peu fiable et risquerait d'enregistrer une adresse
erronee pour un canal de securite. Le numero de telephone, deja
collecte, sert de canal de contact principal. Cette liste de champs peut
etre etendue ou modifiee sans changer la logique du formulaire : il
suffit d'ajouter une entree dans les listes `kPersonalInfoFields` ou
`kBankAccountFields`.

Chaque champ repondu est enregistre immediatement. Si l'utilisateur
ferme l'application ou que le service est interrompu au milieu du
formulaire, dire de nouveau le mot-cle reprend exactement a la question
suivante, sans repeter les questions deja repondues.

## Structure du depot

```
banqueparle/
  .github/workflows/build-apk.yml         Pipeline CI : build APK automatique
  android_overrides/
    main/AndroidManifest.xml              Permissions et declarations Android
    main/kotlin/MainActivity.kt           Activite requise par local_auth
    test/widget_test.dart                 Test minimal correspondant a l'app
  lib/
    main.dart                             Point d'entree
    services/
      wake_word_service.dart              Detection du mot-cle, formulaire headless
      onboarding_fields.dart              Definition des champs et moteur de formulaire
      fingerprint_enrollment_flow.dart    Enrolement empreinte digitale (premier plan)
      pin_enrollment_flow.dart            Definition du code secret (premier plan)
      voice_dialog.dart                   Dialogue vocal generique (question/reponse)
      stt_helper.dart                     Ecoute unique partagee entre les deux isolats
      tts_service.dart                    Synthese vocale (premier plan)
    screens/home_screen.dart              Interface (deux couleurs, orchestration)
    utils/
      app_colors.dart                     Charte graphique centralisee
      onboarding_storage.dart             Stockage persistant partage
      permissions_helper.dart             Gestion des permissions systeme
  pubspec.yaml
  .gitignore
```

Les dossiers `android/`, `ios/`, `build/` ne sont pas committes : ils
sont regeneres a chaque execution du workflow CI (`flutter create`), qui
applique ensuite les fichiers de `android_overrides/` par-dessus.

## Mise en route

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<utilisateur>/banqueparle.git
git push -u origin main
```

Chaque push declenche le workflow. L'APK signe en mode release est
disponible dans l'onglet Actions du depot, section Artifacts. Un tag
(`git tag v1.0.0 && git push origin v1.0.0`) publie en plus une Release
GitHub avec l'APK attache.

## Limite technique a connaitre : notifications plein ecran

Depuis Android 14, la permission systeme qui autorise une notification a
ouvrir automatiquement une application (utilisee ici pour reveiller
BanqueParle) est refusee par defaut pour toute application qui n'est pas
un telephone ou un reveil. L'utilisateur doit l'activer une fois,
manuellement, via le bouton "Autoriser l'ouverture automatique" present
dans l'application (qui ouvre directement les reglages systeme
correspondants).

C'est pourquoi le service d'arriere-plan ne depend pas de cette
ouverture automatique pour fonctionner : il prononce lui-meme toutes les
questions et confirmations vocales, avant meme que l'interface ne
s'affiche. L'ouverture visuelle de l'application reste necessaire
uniquement pour l'etape de l'empreinte digitale, qui est une contrainte
materielle d'Android (l'authentification biometrique ne peut etre
invoquee que depuis un ecran affiche).

## Limite technique a connaitre : enrolement de l'empreinte digitale

Aucune application tierce ne peut enroler un nouveau doigt dans le
capteur d'empreinte d'un telephone Android : cette operation reste
reservee aux reglages systeme, proteges par le code de l'utilisateur,
pour des raisons de securite materielle. Le flux implemente ici
authentifie donc l'utilisateur avec les empreintes deja enregistrees sur
son telephone (ouverture du lecteur natif par defaut de l'appareil), ce
qui couvre l'usage demande : associer une empreinte a un profil
BanqueParle, avec confirmation vocale, jusqu'a trois enregistrements
successifs. C'est pour cette raison qu'un code secret de secours a
quatre chiffres a ete ajoute comme deuxieme facteur obligatoire : une
application bancaire ne peut pas reposer sur la seule disponibilite
d'un capteur biometrique.

## Fonctionnalites hors perimetre de cette livraison

Conformement au cahier des charges : consultation du solde, historique
des operations, virement vocal, generation de code a usage unique,
gestion du profil, mise en relation avec un conseiller, pave numerique
de secours.
