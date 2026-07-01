import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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
    Locale('en'),
    Locale('es')
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Geo Tag'**
  String get appTitle;

  /// Bottom nav: Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom nav: Map tab
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// Bottom nav: Earnings tab
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get navEarnings;

  /// Bottom nav: Log tab
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get navLog;

  /// Bottom nav: Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Bottom nav: Upload tab
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get navUpload;

  /// Login screen heading
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginTitle;

  /// Login screen subheading
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue'**
  String get loginSubtitle;

  /// Login button label
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginButton;

  /// Sign out button label
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get logoutButton;

  /// Email field placeholder
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailHint;

  /// Password field placeholder
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordHint;

  /// Upload screen title
  ///
  /// In en, this message translates to:
  /// **'Upload Photo'**
  String get uploadTitle;

  /// Button to pick a photo
  ///
  /// In en, this message translates to:
  /// **'Select Photo'**
  String get uploadSelectPhoto;

  /// Take photo with camera
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get uploadCamera;

  /// Pick from gallery
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get uploadGallery;

  /// Profile picker label on upload screen
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get uploadProfile;

  /// Address field label on upload screen
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get uploadAddress;

  /// Note field label on upload screen
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get uploadNote;

  /// Final upload button
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get uploadButton;

  /// Upload progress indicator
  ///
  /// In en, this message translates to:
  /// **'Uploading {current} of {total}…'**
  String uploadingProgress(int current, int total);

  /// Button to create a new profile from upload screen
  ///
  /// In en, this message translates to:
  /// **'+ New Profile'**
  String get uploadNewProfile;

  /// Profile name field label
  ///
  /// In en, this message translates to:
  /// **'Profile Name'**
  String get profileName;

  /// Confirm button when creating a new profile
  ///
  /// In en, this message translates to:
  /// **'Create Profile'**
  String get profileCreate;

  /// Label for a profile's primary address
  ///
  /// In en, this message translates to:
  /// **'Primary Address'**
  String get profilePrimaryAddress;

  /// Empty state on profile detail screen
  ///
  /// In en, this message translates to:
  /// **'No photos yet'**
  String get profileNoPhotos;

  /// Photo count on profile screen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 photo} other{{count} photos}}'**
  String profilePhotosCount(int count);

  /// Service type label: ASAP/rush
  ///
  /// In en, this message translates to:
  /// **'ASAP'**
  String get svcAsap;

  /// Service type label: standard
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get svcStandard;

  /// Service type label: airport
  ///
  /// In en, this message translates to:
  /// **'Airport'**
  String get svcAirport;

  /// Job status: open
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get statusOpen;

  /// Job status: in progress
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get statusInProgress;

  /// Job status: completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// Job status: archived
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get statusArchived;

  /// Section header for job status card
  ///
  /// In en, this message translates to:
  /// **'JOB STATUS'**
  String get jobStatus;

  /// Section header for status summary card
  ///
  /// In en, this message translates to:
  /// **'STATUS SUMMARY'**
  String get statusSummary;

  /// Subtitle of status summary card
  ///
  /// In en, this message translates to:
  /// **'Full job lifecycle'**
  String get statusSummarySubtitle;

  /// Hint text below status stepper
  ///
  /// In en, this message translates to:
  /// **'Tap any step to change the status'**
  String get statusTapHint;

  /// Timeline label: job opened
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get statusOpened;

  /// Location section label on photo detail
  ///
  /// In en, this message translates to:
  /// **'LOCATION'**
  String get locationLabel;

  /// Button to open coordinates in maps
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// Button to copy GPS coordinates
  ///
  /// In en, this message translates to:
  /// **'Copy Coords'**
  String get copyCoords;

  /// Snackbar after copying coords
  ///
  /// In en, this message translates to:
  /// **'Coordinates copied to clipboard'**
  String get coordsCopied;

  /// Snackbar after copying maps URL
  ///
  /// In en, this message translates to:
  /// **'Maps link copied — paste in your browser'**
  String get mapLinkCopied;

  /// Note section label
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteLabel;

  /// Note field placeholder
  ///
  /// In en, this message translates to:
  /// **'Add a note…'**
  String get notePlaceholder;

  /// Button to save note
  ///
  /// In en, this message translates to:
  /// **'Save Note'**
  String get saveNote;

  /// Snackbar after saving note
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get noteSaved;

  /// Address field label in edit sheet
  ///
  /// In en, this message translates to:
  /// **'Address & ZIP'**
  String get addressLabel;

  /// Button to save address
  ///
  /// In en, this message translates to:
  /// **'Save Address'**
  String get saveAddress;

  /// Snackbar after saving address
  ///
  /// In en, this message translates to:
  /// **'Address saved'**
  String get addressSaved;

  /// Button to auto-fill address from GPS
  ///
  /// In en, this message translates to:
  /// **'Auto-fill'**
  String get addressAutoFill;

  /// Delete photo button label
  ///
  /// In en, this message translates to:
  /// **'Delete Photo'**
  String get deletePhoto;

  /// Delete confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Photo'**
  String get deleteConfirmTitle;

  /// Delete confirmation dialog body
  ///
  /// In en, this message translates to:
  /// **'This photo will be permanently deleted. This action cannot be undone.'**
  String get deleteConfirmBody;

  /// Confirm delete button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteConfirm;

  /// Generic cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Edit sheet title
  ///
  /// In en, this message translates to:
  /// **'Edit Photo'**
  String get editPhoto;

  /// Replace photo option
  ///
  /// In en, this message translates to:
  /// **'Replace Photo'**
  String get replacePhoto;

  /// Subtitle for replace photo option
  ///
  /// In en, this message translates to:
  /// **'Swap the image with a new one'**
  String get replacePhotoSubtitle;

  /// Snackbar after replacing photo
  ///
  /// In en, this message translates to:
  /// **'Photo updated successfully'**
  String get photoUpdated;

  /// Snackbar after deleting photo
  ///
  /// In en, this message translates to:
  /// **'Photo deleted'**
  String get photoDeleted;

  /// Edit location option label
  ///
  /// In en, this message translates to:
  /// **'Edit Location'**
  String get editLocation;

  /// Snackbar after editing timestamp
  ///
  /// In en, this message translates to:
  /// **'Timestamp updated'**
  String get timestampUpdated;

  /// Label for captured timestamp on photo detail
  ///
  /// In en, this message translates to:
  /// **'Captured'**
  String get capturedLabel;

  /// Label for payout amount
  ///
  /// In en, this message translates to:
  /// **'Payout'**
  String get payoutLabel;

  /// Section header for linked profiles on photo detail
  ///
  /// In en, this message translates to:
  /// **'LINKED PROFILES'**
  String get linkedProfiles;

  /// CSV export button/action label
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get csvExportTitle;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// Go back button label
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// Error message when photo cannot be found
  ///
  /// In en, this message translates to:
  /// **'Photo not found'**
  String get photoNotFound;

  /// Subtitle for photo not found state
  ///
  /// In en, this message translates to:
  /// **'This photo may have been deleted.'**
  String get photoNotFoundSubtitle;

  /// Error message when photo fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load photo'**
  String get failedToLoadPhoto;

  /// Error state on profile detail screen
  ///
  /// In en, this message translates to:
  /// **'Could not load photos'**
  String get couldNotLoadPhotos;

  /// Address resolution progress text
  ///
  /// In en, this message translates to:
  /// **'Fetching address…'**
  String get fetchingAddress;

  /// GPS locating progress text
  ///
  /// In en, this message translates to:
  /// **'Locating…'**
  String get locating;

  /// Snackbar after updating job status
  ///
  /// In en, this message translates to:
  /// **'Status updated to {status}'**
  String statusUpdatedTo(String status);

  /// Camera source option
  ///
  /// In en, this message translates to:
  /// **'Take a new photo'**
  String get takeNewPhoto;

  /// Gallery source option
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get chooseFromGallery;
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
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
