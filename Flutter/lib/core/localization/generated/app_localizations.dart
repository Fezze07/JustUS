import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('it'),
    Locale('en')
  ];

  /// Nome dell'app mostrato dal sistema.
  ///
  /// In it, this message translates to:
  /// **'JustUs'**
  String get appTitle;

  /// Chiave dimostrativa per l'uso context.loc.example.
  ///
  /// In it, this message translates to:
  /// **'Esempio'**
  String get example;

  /// Titolo della schermata impostazioni.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get settingsTitle;

  /// Sottotitolo descrittivo della schermata impostazioni.
  ///
  /// In it, this message translates to:
  /// **'Preferenze dell\'app e lingua'**
  String get settingsSubtitle;

  /// Intestazione della sezione lingua.
  ///
  /// In it, this message translates to:
  /// **'LINGUA'**
  String get languageSectionTitle;

  /// Titolo della voce impostazioni per la lingua.
  ///
  /// In it, this message translates to:
  /// **'Lingua'**
  String get languageSettingTitle;

  /// Sottotitolo della voce impostazioni per la lingua.
  ///
  /// In it, this message translates to:
  /// **'Cambia lingua in tempo reale'**
  String get languageSettingSubtitle;

  /// Etichetta della lingua attualmente selezionata.
  ///
  /// In it, this message translates to:
  /// **'Lingua corrente'**
  String get currentLanguageLabel;

  /// Nome della lingua italiana.
  ///
  /// In it, this message translates to:
  /// **'Italiano'**
  String get italianLanguage;

  /// Nome della lingua inglese.
  ///
  /// In it, this message translates to:
  /// **'Inglese'**
  String get englishLanguage;

  /// Messaggio snackbar dopo il cambio lingua.
  ///
  /// In it, this message translates to:
  /// **'Lingua aggiornata'**
  String get languageSavedMessage;

  /// Titolo sezione preparatoria per traduzioni AI.
  ///
  /// In it, this message translates to:
  /// **'TRADUZIONI AI'**
  String get aiTranslationSectionTitle;

  /// Titolo card informativa sul supporto AI futuro.
  ///
  /// In it, this message translates to:
  /// **'Pronto per traduzioni future'**
  String get aiTranslationReadyTitle;

  /// Descrizione card informativa sul supporto AI futuro.
  ///
  /// In it, this message translates to:
  /// **'Le chiavi ARB sono organizzate per espandere nuove lingue e workflow AI.'**
  String get aiTranslationReadySubtitle;

  /// Titolo header della schermata profilo.
  ///
  /// In it, this message translates to:
  /// **'Profilo e impostazioni'**
  String get profileSettingsTitle;

  /// Titolo della sezione impostazioni di sistema.
  ///
  /// In it, this message translates to:
  /// **'SISTEMA'**
  String get systemOverrideSectionTitle;

  /// No description provided for @appTagline.
  ///
  /// In it, this message translates to:
  /// **'Momenti condivisi, cuori più vicini'**
  String get appTagline;

  /// No description provided for @common_you.
  ///
  /// In it, this message translates to:
  /// **'TU'**
  String get common_you;

  /// No description provided for @common_youTitle.
  ///
  /// In it, this message translates to:
  /// **'Tu'**
  String get common_youTitle;

  /// No description provided for @common_partner.
  ///
  /// In it, this message translates to:
  /// **'Partner'**
  String get common_partner;

  /// No description provided for @common_partnerUpper.
  ///
  /// In it, this message translates to:
  /// **'PARTNER'**
  String get common_partnerUpper;

  /// No description provided for @common_cancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get common_cancel;

  /// No description provided for @common_close.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get common_close;

  /// No description provided for @common_retry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get common_retry;

  /// No description provided for @common_add.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi'**
  String get common_add;

  /// No description provided for @common_delete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get common_delete;

  /// No description provided for @common_file.
  ///
  /// In it, this message translates to:
  /// **'File'**
  String get common_file;

  /// No description provided for @common_audio.
  ///
  /// In it, this message translates to:
  /// **'Audio'**
  String get common_audio;

  /// No description provided for @auth_loginTitle.
  ///
  /// In it, this message translates to:
  /// **'Bentornato'**
  String get auth_loginTitle;

  /// No description provided for @auth_loginSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Accedi per riconnetterti con il tuo partner'**
  String get auth_loginSubtitle;

  /// No description provided for @auth_loginNoAccount.
  ///
  /// In it, this message translates to:
  /// **'Non hai un account?'**
  String get auth_loginNoAccount;

  /// No description provided for @auth_signUp.
  ///
  /// In it, this message translates to:
  /// **'Registrati'**
  String get auth_signUp;

  /// No description provided for @auth_emailLabel.
  ///
  /// In it, this message translates to:
  /// **'EMAIL'**
  String get auth_emailLabel;

  /// No description provided for @auth_emailTitle.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get auth_emailTitle;

  /// No description provided for @auth_emailHint.
  ///
  /// In it, this message translates to:
  /// **'tu@email.com'**
  String get auth_emailHint;

  /// No description provided for @auth_registerEmailHint.
  ///
  /// In it, this message translates to:
  /// **'mario@example.com'**
  String get auth_registerEmailHint;

  /// No description provided for @auth_passwordLabel.
  ///
  /// In it, this message translates to:
  /// **'PASSWORD'**
  String get auth_passwordLabel;

  /// No description provided for @auth_passwordTitle.
  ///
  /// In it, this message translates to:
  /// **'Password'**
  String get auth_passwordTitle;

  /// No description provided for @auth_passwordHint.
  ///
  /// In it, this message translates to:
  /// **'••••••••'**
  String get auth_passwordHint;

  /// No description provided for @auth_forgotPassword.
  ///
  /// In it, this message translates to:
  /// **'Password dimenticata?'**
  String get auth_forgotPassword;

  /// No description provided for @auth_loginButton.
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get auth_loginButton;

  /// No description provided for @auth_registerTitle.
  ///
  /// In it, this message translates to:
  /// **'Unisciti a JustUS'**
  String get auth_registerTitle;

  /// No description provided for @auth_registerSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Inizia il vostro percorso verso una connessione più profonda.'**
  String get auth_registerSubtitle;

  /// No description provided for @auth_alreadyAccount.
  ///
  /// In it, this message translates to:
  /// **'Hai già un account?'**
  String get auth_alreadyAccount;

  /// No description provided for @auth_logIn.
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get auth_logIn;

  /// No description provided for @auth_nameLabel.
  ///
  /// In it, this message translates to:
  /// **'IL TUO NOME'**
  String get auth_nameLabel;

  /// No description provided for @auth_nameHint.
  ///
  /// In it, this message translates to:
  /// **'Mario Rossi'**
  String get auth_nameHint;

  /// No description provided for @auth_createAccount.
  ///
  /// In it, this message translates to:
  /// **'Crea account'**
  String get auth_createAccount;

  /// No description provided for @auth_nameFieldName.
  ///
  /// In it, this message translates to:
  /// **'Nome'**
  String get auth_nameFieldName;

  /// No description provided for @auth_confirmEmailTitle.
  ///
  /// In it, this message translates to:
  /// **'Controlla la tua email'**
  String get auth_confirmEmailTitle;

  /// No description provided for @auth_goToLogin.
  ///
  /// In it, this message translates to:
  /// **'Vai al login'**
  String get auth_goToLogin;

  /// No description provided for @auth_changePasswordTitle.
  ///
  /// In it, this message translates to:
  /// **'Cambia password'**
  String get auth_changePasswordTitle;

  /// No description provided for @auth_changePasswordSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Crea una nuova password unica e sicura.'**
  String get auth_changePasswordSubtitle;

  /// No description provided for @auth_currentPasswordLabel.
  ///
  /// In it, this message translates to:
  /// **'Password attuale'**
  String get auth_currentPasswordLabel;

  /// No description provided for @auth_currentPasswordHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la password attuale'**
  String get auth_currentPasswordHint;

  /// No description provided for @auth_newPasswordLabel.
  ///
  /// In it, this message translates to:
  /// **'Nuova password'**
  String get auth_newPasswordLabel;

  /// No description provided for @auth_newPasswordHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la nuova password'**
  String get auth_newPasswordHint;

  /// No description provided for @auth_confirmPasswordLabel.
  ///
  /// In it, this message translates to:
  /// **'Conferma password'**
  String get auth_confirmPasswordLabel;

  /// No description provided for @auth_confirmPasswordHint.
  ///
  /// In it, this message translates to:
  /// **'Reinserisci la nuova password'**
  String get auth_confirmPasswordHint;

  /// No description provided for @auth_updatePassword.
  ///
  /// In it, this message translates to:
  /// **'Aggiorna password'**
  String get auth_updatePassword;

  /// No description provided for @auth_passwordUpdated.
  ///
  /// In it, this message translates to:
  /// **'Password aggiornata con successo!'**
  String get auth_passwordUpdated;

  /// No description provided for @auth_captchaTitle.
  ///
  /// In it, this message translates to:
  /// **'Verifica di sicurezza'**
  String get auth_captchaTitle;

  /// No description provided for @auth_captchaMessage.
  ///
  /// In it, this message translates to:
  /// **'JustUs sta verificando che tu sia un umano...'**
  String get auth_captchaMessage;

  /// No description provided for @auth_captchaMissingConfig.
  ///
  /// In it, this message translates to:
  /// **'Configurazione di sicurezza mancante (Site Key).'**
  String get auth_captchaMissingConfig;

  /// No description provided for @auth_captchaFailed.
  ///
  /// In it, this message translates to:
  /// **'Verifica captcha non riuscita'**
  String get auth_captchaFailed;

  /// No description provided for @auth_loginNoUserData.
  ///
  /// In it, this message translates to:
  /// **'Login fallito: dati utente mancanti'**
  String get auth_loginNoUserData;

  /// No description provided for @auth_registerUserNotCreated.
  ///
  /// In it, this message translates to:
  /// **'Registrazione fallita: utente non creato'**
  String get auth_registerUserNotCreated;

  /// No description provided for @auth_tooManyLoginAttempts.
  ///
  /// In it, this message translates to:
  /// **'Troppi tentativi di login. Riprova tra poco.'**
  String get auth_tooManyLoginAttempts;

  /// No description provided for @auth_validationEmailRequired.
  ///
  /// In it, this message translates to:
  /// **'L\'email è obbligatoria'**
  String get auth_validationEmailRequired;

  /// No description provided for @auth_validationEmailInvalid.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un\'email valida'**
  String get auth_validationEmailInvalid;

  /// No description provided for @auth_validationPasswordRequired.
  ///
  /// In it, this message translates to:
  /// **'La password è obbligatoria'**
  String get auth_validationPasswordRequired;

  /// No description provided for @auth_validationPasswordMinLength.
  ///
  /// In it, this message translates to:
  /// **'La password deve avere almeno 8 caratteri'**
  String get auth_validationPasswordMinLength;

  /// No description provided for @auth_validationPasswordLowercase.
  ///
  /// In it, this message translates to:
  /// **'Deve contenere almeno una minuscola'**
  String get auth_validationPasswordLowercase;

  /// No description provided for @auth_validationPasswordUppercase.
  ///
  /// In it, this message translates to:
  /// **'Deve contenere almeno una maiuscola'**
  String get auth_validationPasswordUppercase;

  /// No description provided for @auth_validationPasswordNumber.
  ///
  /// In it, this message translates to:
  /// **'Deve contenere almeno un numero'**
  String get auth_validationPasswordNumber;

  /// No description provided for @auth_validationPasswordSymbol.
  ///
  /// In it, this message translates to:
  /// **'Deve contenere almeno un simbolo'**
  String get auth_validationPasswordSymbol;

  /// No description provided for @home_daysTogether.
  ///
  /// In it, this message translates to:
  /// **'GIORNI INSIEME'**
  String get home_daysTogether;

  /// No description provided for @home_currentMoodTitle.
  ///
  /// In it, this message translates to:
  /// **'IL NOSTRO MOOD ATTUALE'**
  String get home_currentMoodTitle;

  /// No description provided for @home_updateStatus.
  ///
  /// In it, this message translates to:
  /// **'Aggiorna stato'**
  String get home_updateStatus;

  /// No description provided for @home_quickActions.
  ///
  /// In it, this message translates to:
  /// **'AZIONI RAPIDE'**
  String get home_quickActions;

  /// No description provided for @home_viewAll.
  ///
  /// In it, this message translates to:
  /// **'Vedi tutto'**
  String get home_viewAll;

  /// No description provided for @home_gamesTitle.
  ///
  /// In it, this message translates to:
  /// **'Giochi'**
  String get home_gamesTitle;

  /// No description provided for @home_gamesSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Gioca a un quiz di coppia'**
  String get home_gamesSubtitle;

  /// No description provided for @home_photosTitle.
  ///
  /// In it, this message translates to:
  /// **'Foto'**
  String get home_photosTitle;

  /// No description provided for @home_photosSubtitle.
  ///
  /// In it, this message translates to:
  /// **'La nostra galleria condivisa'**
  String get home_photosSubtitle;

  /// No description provided for @home_bucketListTitle.
  ///
  /// In it, this message translates to:
  /// **'Bucket List'**
  String get home_bucketListTitle;

  /// No description provided for @home_bucketListSubtitleDynamic.
  ///
  /// In it, this message translates to:
  /// **'{count} attività in sospeso'**
  String home_bucketListSubtitleDynamic(int count);

  /// No description provided for @home_nudgeTitle.
  ///
  /// In it, this message translates to:
  /// **'Mi manchi...'**
  String get home_nudgeTitle;

  /// No description provided for @home_nudgeSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Dillo con un click'**
  String get home_nudgeSubtitle;

  /// No description provided for @home_missYouSent.
  ///
  /// In it, this message translates to:
  /// **'Mi manchi inviato!'**
  String get home_missYouSent;

  /// No description provided for @settings_notificationsTitle.
  ///
  /// In it, this message translates to:
  /// **'Notifiche'**
  String get settings_notificationsTitle;

  /// No description provided for @settings_notificationsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Attività e promemoria neurali'**
  String get settings_notificationsSubtitle;

  /// No description provided for @settings_darkModeTitle.
  ///
  /// In it, this message translates to:
  /// **'Modalità scura'**
  String get settings_darkModeTitle;

  /// No description provided for @settings_darkModeSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Ottimizzata violet-punk'**
  String get settings_darkModeSubtitle;

  /// No description provided for @profile_connected.
  ///
  /// In it, this message translates to:
  /// **'CONNESSI'**
  String get profile_connected;

  /// No description provided for @profile_coreConnectionSection.
  ///
  /// In it, this message translates to:
  /// **'CONNESSIONE'**
  String get profile_coreConnectionSection;

  /// No description provided for @profile_debugUtilitiesSection.
  ///
  /// In it, this message translates to:
  /// **'UTILITY DEBUG'**
  String get profile_debugUtilitiesSection;

  /// No description provided for @profile_yourPartnerCodeTitle.
  ///
  /// In it, this message translates to:
  /// **'Il tuo codice partner'**
  String get profile_yourPartnerCodeTitle;

  /// No description provided for @profile_changePasswordSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Proteggi il vostro spazio condiviso'**
  String get profile_changePasswordSubtitle;

  /// No description provided for @profile_anniversaryTitle.
  ///
  /// In it, this message translates to:
  /// **'Anniversario'**
  String get profile_anniversaryTitle;

  /// No description provided for @profile_anniversaryEmpty.
  ///
  /// In it, this message translates to:
  /// **'Imposta la vostra data speciale'**
  String get profile_anniversaryEmpty;

  /// No description provided for @profile_wipeDataTitle.
  ///
  /// In it, this message translates to:
  /// **'Cancella dati app'**
  String get profile_wipeDataTitle;

  /// No description provided for @profile_wipeDataSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Resetta tutto tranne l’account'**
  String get profile_wipeDataSubtitle;

  /// No description provided for @profile_wipeConfirmTitle.
  ///
  /// In it, this message translates to:
  /// **'CANCELLARE TUTTI I DATI?'**
  String get profile_wipeConfirmTitle;

  /// No description provided for @profile_wipeConfirmContent.
  ///
  /// In it, this message translates to:
  /// **'Questa azione eliminerà definitivamente elementi del drive, bucket list, giochi e mood.\n\nLogin e connessione saranno preservati.'**
  String get profile_wipeConfirmContent;

  /// No description provided for @profile_wipeCancel.
  ///
  /// In it, this message translates to:
  /// **'ANNULLA'**
  String get profile_wipeCancel;

  /// No description provided for @profile_wipeConfirm.
  ///
  /// In it, this message translates to:
  /// **'CANCELLA TUTTO'**
  String get profile_wipeConfirm;

  /// No description provided for @profile_dataWiped.
  ///
  /// In it, this message translates to:
  /// **'Dati cancellati. Sincronizzazione...'**
  String get profile_dataWiped;

  /// No description provided for @profile_disconnectSession.
  ///
  /// In it, this message translates to:
  /// **'DISCONNETTI SESSIONE'**
  String get profile_disconnectSession;

  /// No description provided for @partner_title.
  ///
  /// In it, this message translates to:
  /// **'Con chi vuoi connetterti\noggi?'**
  String get partner_title;

  /// No description provided for @partner_connected.
  ///
  /// In it, this message translates to:
  /// **'CONNESSI'**
  String get partner_connected;

  /// No description provided for @partner_newConnection.
  ///
  /// In it, this message translates to:
  /// **'Nuova connessione'**
  String get partner_newConnection;

  /// No description provided for @partner_addPartner.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi partner'**
  String get partner_addPartner;

  /// No description provided for @partner_receivedRequests.
  ///
  /// In it, this message translates to:
  /// **'RICHIESTE RICEVUTE'**
  String get partner_receivedRequests;

  /// No description provided for @partner_sentRequests.
  ///
  /// In it, this message translates to:
  /// **'RICHIESTE INVIATE'**
  String get partner_sentRequests;

  /// No description provided for @partner_noPendingInvites.
  ///
  /// In it, this message translates to:
  /// **'Nessun invito in sospeso'**
  String get partner_noPendingInvites;

  /// No description provided for @partner_logout.
  ///
  /// In it, this message translates to:
  /// **'Logout'**
  String get partner_logout;

  /// No description provided for @partner_acceptError.
  ///
  /// In it, this message translates to:
  /// **'Errore durante l\'accettazione dell\'invito'**
  String get partner_acceptError;

  /// No description provided for @partner_personalCodeTitle.
  ///
  /// In it, this message translates to:
  /// **'IL TUO CODICE PERSONALE'**
  String get partner_personalCodeTitle;

  /// No description provided for @partner_codeCopied.
  ///
  /// In it, this message translates to:
  /// **'Codice copiato negli appunti!'**
  String get partner_codeCopied;

  /// No description provided for @partner_personalCodeSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Invia questo codice al tuo partner per connettervi su JustUS!'**
  String get partner_personalCodeSubtitle;

  /// No description provided for @partner_inviteTitle.
  ///
  /// In it, this message translates to:
  /// **'Invita partner'**
  String get partner_inviteTitle;

  /// No description provided for @partner_inviteDescription.
  ///
  /// In it, this message translates to:
  /// **'Inserisci l\'email e il codice del tuo partner per inviare una richiesta.'**
  String get partner_inviteDescription;

  /// No description provided for @partner_emailLabel.
  ///
  /// In it, this message translates to:
  /// **'EMAIL PARTNER'**
  String get partner_emailLabel;

  /// No description provided for @partner_emailHint.
  ///
  /// In it, this message translates to:
  /// **'partner@example.com'**
  String get partner_emailHint;

  /// No description provided for @partner_codeLabel.
  ///
  /// In it, this message translates to:
  /// **'CODICE PARTNER'**
  String get partner_codeLabel;

  /// No description provided for @partner_codeHint.
  ///
  /// In it, this message translates to:
  /// **'ABC123'**
  String get partner_codeHint;

  /// No description provided for @partner_send.
  ///
  /// In it, this message translates to:
  /// **'Invia'**
  String get partner_send;

  /// No description provided for @partner_fillAllFields.
  ///
  /// In it, this message translates to:
  /// **'Compila tutti i campi'**
  String get partner_fillAllFields;

  /// No description provided for @partner_inviteSuccess.
  ///
  /// In it, this message translates to:
  /// **'Invito inviato con successo!'**
  String get partner_inviteSuccess;

  /// No description provided for @partner_wantsToConnect.
  ///
  /// In it, this message translates to:
  /// **'Vuole connettersi'**
  String get partner_wantsToConnect;

  /// No description provided for @partner_waitingResponse.
  ///
  /// In it, this message translates to:
  /// **'In attesa di risposta'**
  String get partner_waitingResponse;

  /// No description provided for @partner_acceptTooltip.
  ///
  /// In it, this message translates to:
  /// **'Accetta'**
  String get partner_acceptTooltip;

  /// No description provided for @partner_declineTooltip.
  ///
  /// In it, this message translates to:
  /// **'Rifiuta'**
  String get partner_declineTooltip;

  /// No description provided for @partner_cancelRequestTooltip.
  ///
  /// In it, this message translates to:
  /// **'Annulla richiesta'**
  String get partner_cancelRequestTooltip;

  /// No description provided for @partner_requestButton.
  ///
  /// In it, this message translates to:
  /// **'Richiedi'**
  String get partner_requestButton;

  /// No description provided for @drive_title.
  ///
  /// In it, this message translates to:
  /// **'I nostri ricordi'**
  String get drive_title;

  /// No description provided for @drive_subtitle.
  ///
  /// In it, this message translates to:
  /// **'ARCHIVIO VIOLA'**
  String get drive_subtitle;

  /// No description provided for @drive_select.
  ///
  /// In it, this message translates to:
  /// **'SELEZIONA'**
  String get drive_select;

  /// No description provided for @drive_filterAll.
  ///
  /// In it, this message translates to:
  /// **'Tutti'**
  String get drive_filterAll;

  /// No description provided for @drive_filterPhotos.
  ///
  /// In it, this message translates to:
  /// **'Foto'**
  String get drive_filterPhotos;

  /// No description provided for @drive_filterVideos.
  ///
  /// In it, this message translates to:
  /// **'Video'**
  String get drive_filterVideos;

  /// No description provided for @drive_filterLikes.
  ///
  /// In it, this message translates to:
  /// **'Like'**
  String get drive_filterLikes;

  /// No description provided for @drive_latestVibes.
  ///
  /// In it, this message translates to:
  /// **'ULTIME VIBE'**
  String get drive_latestVibes;

  /// No description provided for @drive_emptyTitle.
  ///
  /// In it, this message translates to:
  /// **'Ancora nessuna vibe'**
  String get drive_emptyTitle;

  /// No description provided for @drive_uploading.
  ///
  /// In it, this message translates to:
  /// **'Caricamento...'**
  String get drive_uploading;

  /// No description provided for @drive_invalidMediaUrl.
  ///
  /// In it, this message translates to:
  /// **'URL media non valido'**
  String get drive_invalidMediaUrl;

  /// No description provided for @drive_deleteTitle.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get drive_deleteTitle;

  /// No description provided for @drive_deleteConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare questo elemento?'**
  String get drive_deleteConfirm;

  /// No description provided for @drive_videoError.
  ///
  /// In it, this message translates to:
  /// **'Errore video'**
  String get drive_videoError;

  /// No description provided for @drive_audioError.
  ///
  /// In it, this message translates to:
  /// **'Errore audio'**
  String get drive_audioError;

  /// No description provided for @drive_favoritesTitle.
  ///
  /// In it, this message translates to:
  /// **'Preferiti'**
  String get drive_favoritesTitle;

  /// No description provided for @drive_noFavorites.
  ///
  /// In it, this message translates to:
  /// **'Nessun preferito'**
  String get drive_noFavorites;

  /// No description provided for @drive_noFavoritesSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi foto e video ai preferiti dal Drive!'**
  String get drive_noFavoritesSubtitle;

  /// No description provided for @drive_takePhoto.
  ///
  /// In it, this message translates to:
  /// **'Scatta foto'**
  String get drive_takePhoto;

  /// No description provided for @drive_fromGallery.
  ///
  /// In it, this message translates to:
  /// **'Dalla galleria'**
  String get drive_fromGallery;

  /// No description provided for @drive_uploadComplete.
  ///
  /// In it, this message translates to:
  /// **'Upload completato ✓'**
  String get drive_uploadComplete;

  /// No description provided for @drive_deleted.
  ///
  /// In it, this message translates to:
  /// **'Eliminato!'**
  String get drive_deleted;

  /// No description provided for @drive_uploadInProgress.
  ///
  /// In it, this message translates to:
  /// **'Caricamento in corso…'**
  String get drive_uploadInProgress;

  /// No description provided for @bucket_categoryAll.
  ///
  /// In it, this message translates to:
  /// **'Tutti'**
  String get bucket_categoryAll;

  /// No description provided for @bucket_categoryTravel.
  ///
  /// In it, this message translates to:
  /// **'Viaggi'**
  String get bucket_categoryTravel;

  /// No description provided for @bucket_categoryDates.
  ///
  /// In it, this message translates to:
  /// **'Appuntamenti'**
  String get bucket_categoryDates;

  /// No description provided for @bucket_categoryGoals.
  ///
  /// In it, this message translates to:
  /// **'Obiettivi'**
  String get bucket_categoryGoals;

  /// No description provided for @bucket_categoryCrazy.
  ///
  /// In it, this message translates to:
  /// **'Follie'**
  String get bucket_categoryCrazy;

  /// No description provided for @bucket_categoryAdventure.
  ///
  /// In it, this message translates to:
  /// **'Avventura'**
  String get bucket_categoryAdventure;

  /// No description provided for @bucket_categoryRomantic.
  ///
  /// In it, this message translates to:
  /// **'Romantico'**
  String get bucket_categoryRomantic;

  /// No description provided for @bucket_categoryHomemade.
  ///
  /// In it, this message translates to:
  /// **'Fatto in casa'**
  String get bucket_categoryHomemade;

  /// No description provided for @bucket_addGoalTitle.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi obiettivo'**
  String get bucket_addGoalTitle;

  /// No description provided for @bucket_goalHint.
  ///
  /// In it, this message translates to:
  /// **'Cosa vuoi fare insieme?'**
  String get bucket_goalHint;

  /// No description provided for @bucket_categoryLabel.
  ///
  /// In it, this message translates to:
  /// **'Categoria:'**
  String get bucket_categoryLabel;

  /// No description provided for @bucket_add.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi'**
  String get bucket_add;

  /// No description provided for @bucket_title.
  ///
  /// In it, this message translates to:
  /// **'I nostri obiettivi'**
  String get bucket_title;

  /// No description provided for @bucket_emptyAll.
  ///
  /// In it, this message translates to:
  /// **'Nessun obiettivo creato ancora...\nAggiungine uno!'**
  String get bucket_emptyAll;

  /// No description provided for @bucket_emptyCategory.
  ///
  /// In it, this message translates to:
  /// **'Nessun obiettivo in questa categoria.'**
  String get bucket_emptyCategory;

  /// No description provided for @bucket_enterText.
  ///
  /// In it, this message translates to:
  /// **'Inserisci del testo'**
  String get bucket_enterText;

  /// No description provided for @bucket_addError.
  ///
  /// In it, this message translates to:
  /// **'Errore durante l\'aggiunta'**
  String get bucket_addError;

  /// No description provided for @bucket_updateError.
  ///
  /// In it, this message translates to:
  /// **'Errore aggiornamento item'**
  String get bucket_updateError;

  /// No description provided for @mood_boardTitle.
  ///
  /// In it, this message translates to:
  /// **'Mood Board'**
  String get mood_boardTitle;

  /// No description provided for @mood_recents.
  ///
  /// In it, this message translates to:
  /// **'I TUOI RECENTI'**
  String get mood_recents;

  /// No description provided for @mood_edit.
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get mood_edit;

  /// No description provided for @mood_howFeeling.
  ///
  /// In it, this message translates to:
  /// **'Come ti senti?'**
  String get mood_howFeeling;

  /// No description provided for @mood_timeline.
  ///
  /// In it, this message translates to:
  /// **'Timeline'**
  String get mood_timeline;

  /// No description provided for @mood_today.
  ///
  /// In it, this message translates to:
  /// **'Oggi'**
  String get mood_today;

  /// No description provided for @mood_sheetTitle.
  ///
  /// In it, this message translates to:
  /// **'Scegli il tuo Mood'**
  String get mood_sheetTitle;

  /// No description provided for @mood_enterEmoji.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un\'emoji'**
  String get mood_enterEmoji;

  /// No description provided for @mood_enterSingleEmoji.
  ///
  /// In it, this message translates to:
  /// **'Inserisci una sola emoji'**
  String get mood_enterSingleEmoji;

  /// No description provided for @mood_emojiHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un\'emoji...'**
  String get mood_emojiHint;

  /// No description provided for @mood_duplicateTechnicalMessage.
  ///
  /// In it, this message translates to:
  /// **'Utente ha tentato di reinserire il mood corrente.'**
  String get mood_duplicateTechnicalMessage;

  /// No description provided for @mood_updated.
  ///
  /// In it, this message translates to:
  /// **'Mood aggiornato!'**
  String get mood_updated;

  /// No description provided for @mood_noneSet.
  ///
  /// In it, this message translates to:
  /// **'Nessun mood settato'**
  String get mood_noneSet;

  /// No description provided for @mood_showMore.
  ///
  /// In it, this message translates to:
  /// **'Mostra altri'**
  String get mood_showMore;

  /// No description provided for @game_historyTitle.
  ///
  /// In it, this message translates to:
  /// **'STORICO'**
  String get game_historyTitle;

  /// No description provided for @game_noMatches.
  ///
  /// In it, this message translates to:
  /// **'Ancora nessun match. Rispondi alla domanda del giorno!'**
  String get game_noMatches;

  /// No description provided for @game_statusBothAgreed.
  ///
  /// In it, this message translates to:
  /// **'Siete entrambi d’accordo!'**
  String get game_statusBothAgreed;

  /// No description provided for @game_statusDisagreed.
  ///
  /// In it, this message translates to:
  /// **'Un disaccordo giocoso'**
  String get game_statusDisagreed;

  /// No description provided for @game_statusWaiting.
  ///
  /// In it, this message translates to:
  /// **'In attesa del partner'**
  String get game_statusWaiting;

  /// No description provided for @game_statusWaitingForYou.
  ///
  /// In it, this message translates to:
  /// **'In attesa della tua risposta'**
  String get game_statusWaitingForYou;

  /// No description provided for @game_dailyGame.
  ///
  /// In it, this message translates to:
  /// **'GIOCO DEL GIORNO'**
  String get game_dailyGame;

  /// No description provided for @game_generatingQuestion.
  ///
  /// In it, this message translates to:
  /// **'Generando la domanda...'**
  String get game_generatingQuestion;

  /// No description provided for @game_aiGeneratingSubtitle.
  ///
  /// In it, this message translates to:
  /// **'L’IA sta creando qualcosa di speciale per voi'**
  String get game_aiGeneratingSubtitle;

  /// No description provided for @game_questionOfDay.
  ///
  /// In it, this message translates to:
  /// **'Domanda del giorno'**
  String get game_questionOfDay;

  /// No description provided for @game_allCaughtUp.
  ///
  /// In it, this message translates to:
  /// **'Hai completato tutto!'**
  String get game_allCaughtUp;

  /// No description provided for @game_tryFetchingAgain.
  ///
  /// In it, this message translates to:
  /// **'Prova a recuperare di nuovo'**
  String get game_tryFetchingAgain;

  /// No description provided for @game_invalidOption.
  ///
  /// In it, this message translates to:
  /// **'Errore: opzione non valida'**
  String get game_invalidOption;

  /// No description provided for @game_answerSent.
  ///
  /// In it, this message translates to:
  /// **'Risposta inviata!'**
  String get game_answerSent;

  /// No description provided for @game_waitPartner.
  ///
  /// In it, this message translates to:
  /// **'Aspetta che il partner risponda'**
  String get game_waitPartner;

  /// No description provided for @game_noQuestionAvailable.
  ///
  /// In it, this message translates to:
  /// **'Nessuna domanda disponibile'**
  String get game_noQuestionAvailable;

  /// No description provided for @game_noActivePartnership.
  ///
  /// In it, this message translates to:
  /// **'Nessuna partnership attiva trovata'**
  String get game_noActivePartnership;

  /// No description provided for @game_aiGenerationError.
  ///
  /// In it, this message translates to:
  /// **'Errore generazione AI'**
  String get game_aiGenerationError;

  /// No description provided for @update_availableTitle.
  ///
  /// In it, this message translates to:
  /// **'Aggiornamento disponibile!'**
  String get update_availableTitle;

  /// No description provided for @update_newVersion.
  ///
  /// In it, this message translates to:
  /// **'È disponibile una nuova versione di JustUs.'**
  String get update_newVersion;

  /// No description provided for @update_changelogTitle.
  ///
  /// In it, this message translates to:
  /// **'Novità:'**
  String get update_changelogTitle;

  /// No description provided for @update_later.
  ///
  /// In it, this message translates to:
  /// **'Più tardi'**
  String get update_later;

  /// No description provided for @update_now.
  ///
  /// In it, this message translates to:
  /// **'Aggiorna ora'**
  String get update_now;

  /// No description provided for @logout_title.
  ///
  /// In it, this message translates to:
  /// **'Disconnetti sessione'**
  String get logout_title;

  /// No description provided for @logout_message.
  ///
  /// In it, this message translates to:
  /// **'Terminare la sessione corrente?'**
  String get logout_message;

  /// No description provided for @logout_cancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get logout_cancel;

  /// No description provided for @logout_confirm.
  ///
  /// In it, this message translates to:
  /// **'Disconnetti'**
  String get logout_confirm;

  /// No description provided for @error_dialogTitle.
  ///
  /// In it, this message translates to:
  /// **'Errore'**
  String get error_dialogTitle;

  /// No description provided for @error_codePrefix.
  ///
  /// In it, this message translates to:
  /// **'Codice:'**
  String get error_codePrefix;

  /// No description provided for @error_reauthTitle.
  ///
  /// In it, this message translates to:
  /// **'Sessione scaduta'**
  String get error_reauthTitle;

  /// No description provided for @error_reauthAction.
  ///
  /// In it, this message translates to:
  /// **'Accedi di nuovo'**
  String get error_reauthAction;

  /// No description provided for @error_unknownApi.
  ///
  /// In it, this message translates to:
  /// **'Errore API sconosciuto'**
  String get error_unknownApi;

  /// No description provided for @error_noDataReturned.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato restituito'**
  String get error_noDataReturned;

  /// No description provided for @error_malformedResponse.
  ///
  /// In it, this message translates to:
  /// **'Risposta di errore non valida'**
  String get error_malformedResponse;

  /// No description provided for @error_networkUnavailable.
  ///
  /// In it, this message translates to:
  /// **'Rete non disponibile'**
  String get error_networkUnavailable;

  /// No description provided for @error_operationTimedOut.
  ///
  /// In it, this message translates to:
  /// **'Operazione scaduta'**
  String get error_operationTimedOut;

  /// No description provided for @error_sessionExpiredLoginAgain.
  ///
  /// In it, this message translates to:
  /// **'Sessione scaduta. Effettua di nuovo il login.'**
  String get error_sessionExpiredLoginAgain;

  /// No description provided for @error_requestTimeout.
  ///
  /// In it, this message translates to:
  /// **'Richiesta scaduta (timeout). Controlla la connessione.'**
  String get error_requestTimeout;

  /// No description provided for @error_connection.
  ///
  /// In it, this message translates to:
  /// **'Errore di connessione: {message}'**
  String error_connection(String message);

  /// No description provided for @error_authFail001.
  ///
  /// In it, this message translates to:
  /// **'Sessione scaduta. Effettua di nuovo il login.'**
  String get error_authFail001;

  /// No description provided for @error_authFail002.
  ///
  /// In it, this message translates to:
  /// **'Sessione non valida. Effettua il login.'**
  String get error_authFail002;

  /// No description provided for @error_authFail003.
  ///
  /// In it, this message translates to:
  /// **'La sessione è stata revocata. Accedi nuovamente.'**
  String get error_authFail003;

  /// No description provided for @error_authFail004.
  ///
  /// In it, this message translates to:
  /// **'Accesso non consentito.'**
  String get error_authFail004;

  /// No description provided for @error_authFail005.
  ///
  /// In it, this message translates to:
  /// **'Profilo utente non trovato.'**
  String get error_authFail005;

  /// No description provided for @error_authFail006.
  ///
  /// In it, this message translates to:
  /// **'Dispositivo non riconosciuto. Accedi di nuovo.'**
  String get error_authFail006;

  /// No description provided for @error_authPermission001.
  ///
  /// In it, this message translates to:
  /// **'Non hai i permessi per questa operazione.'**
  String get error_authPermission001;

  /// No description provided for @error_dbRead001.
  ///
  /// In it, this message translates to:
  /// **'Errore durante il caricamento dei dati.'**
  String get error_dbRead001;

  /// No description provided for @error_dbWrite001.
  ///
  /// In it, this message translates to:
  /// **'Errore durante il salvataggio.'**
  String get error_dbWrite001;

  /// No description provided for @error_dbNotFound001.
  ///
  /// In it, this message translates to:
  /// **'Risorsa non trovata.'**
  String get error_dbNotFound001;

  /// No description provided for @error_dbTimeout001.
  ///
  /// In it, this message translates to:
  /// **'Il server è lento. Riprova tra poco.'**
  String get error_dbTimeout001;

  /// No description provided for @error_apiValidation001.
  ///
  /// In it, this message translates to:
  /// **'I dati inseriti non sono validi.'**
  String get error_apiValidation001;

  /// No description provided for @error_apiNotFound001.
  ///
  /// In it, this message translates to:
  /// **'Servizio non disponibile.'**
  String get error_apiNotFound001;

  /// No description provided for @error_apiTimeout001.
  ///
  /// In it, this message translates to:
  /// **'La richiesta ha impiegato troppo. Riprova.'**
  String get error_apiTimeout001;

  /// No description provided for @error_apiFail001.
  ///
  /// In it, this message translates to:
  /// **'Si è verificato un errore. Riprova.'**
  String get error_apiFail001;

  /// No description provided for @error_secBlock001.
  ///
  /// In it, this message translates to:
  /// **'Troppe richieste. Attendi prima di riprovare.'**
  String get error_secBlock001;

  /// No description provided for @error_secBlock002.
  ///
  /// In it, this message translates to:
  /// **'Accesso temporaneamente bloccato.'**
  String get error_secBlock002;

  /// No description provided for @error_secPermission001.
  ///
  /// In it, this message translates to:
  /// **'Accesso negato.'**
  String get error_secPermission001;

  /// No description provided for @error_sysFail001.
  ///
  /// In it, this message translates to:
  /// **'Errore interno del server.'**
  String get error_sysFail001;

  /// No description provided for @error_localNetworkError.
  ///
  /// In it, this message translates to:
  /// **'Nessuna connessione a Internet.'**
  String get error_localNetworkError;

  /// No description provided for @error_localTimeout001.
  ///
  /// In it, this message translates to:
  /// **'La connessione è troppo lenta. Riprova.'**
  String get error_localTimeout001;

  /// No description provided for @error_localParseError.
  ///
  /// In it, this message translates to:
  /// **'Risposta del server non valida.'**
  String get error_localParseError;

  /// No description provided for @error_localStorageError.
  ///
  /// In it, this message translates to:
  /// **'Errore nel salvataggio dei dati locali.'**
  String get error_localStorageError;

  /// No description provided for @error_localConfigError.
  ///
  /// In it, this message translates to:
  /// **'Errore di configurazione dell\'app.'**
  String get error_localConfigError;

  /// No description provided for @error_localMoodDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Hai già impostato questa emoji come mood attuale.'**
  String get error_localMoodDuplicate;

  /// No description provided for @error_unknown.
  ///
  /// In it, this message translates to:
  /// **'Si è verificato un errore imprevisto.'**
  String get error_unknown;

  /// No description provided for @auth_confirmEmailMessage.
  ///
  /// In it, this message translates to:
  /// **'Abbiamo inviato un link di conferma a {email}.\n\nClicca sul link per attivare il tuo account, poi torna qui per accedere.'**
  String auth_confirmEmailMessage(String email);

  /// No description provided for @auth_validationRequired.
  ///
  /// In it, this message translates to:
  /// **'Il campo {fieldName} è obbligatorio'**
  String auth_validationRequired(String fieldName);

  /// No description provided for @profile_shareToConnect.
  ///
  /// In it, this message translates to:
  /// **'Condividi per connetterti: {code}'**
  String profile_shareToConnect(String code);

  /// No description provided for @profile_copiedCode.
  ///
  /// In it, this message translates to:
  /// **'Copiato: {code}'**
  String profile_copiedCode(String code);

  /// No description provided for @profile_appVersion.
  ///
  /// In it, this message translates to:
  /// **'JustUS OS {version}'**
  String profile_appVersion(String version);

  /// No description provided for @bucket_createdOn.
  ///
  /// In it, this message translates to:
  /// **'Creato il: {date}'**
  String bucket_createdOn(String date);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
