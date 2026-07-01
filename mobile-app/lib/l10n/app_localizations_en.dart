// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Geo Tag';

  @override
  String get navHome => 'Home';

  @override
  String get navMap => 'Map';

  @override
  String get navEarnings => 'Earnings';

  @override
  String get navLog => 'Log';

  @override
  String get navSettings => 'Settings';

  @override
  String get navUpload => 'Upload';

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to continue';

  @override
  String get loginButton => 'Sign In';

  @override
  String get logoutButton => 'Sign Out';

  @override
  String get emailHint => 'Email address';

  @override
  String get passwordHint => 'Password';

  @override
  String get uploadTitle => 'Upload Photo';

  @override
  String get uploadSelectPhoto => 'Select Photo';

  @override
  String get uploadCamera => 'Camera';

  @override
  String get uploadGallery => 'Gallery';

  @override
  String get uploadProfile => 'Profile';

  @override
  String get uploadAddress => 'Address';

  @override
  String get uploadNote => 'Note';

  @override
  String get uploadButton => 'Upload';

  @override
  String uploadingProgress(int current, int total) {
    return 'Uploading $current of $total…';
  }

  @override
  String get uploadNewProfile => '+ New Profile';

  @override
  String get profileName => 'Profile Name';

  @override
  String get profileCreate => 'Create Profile';

  @override
  String get profilePrimaryAddress => 'Primary Address';

  @override
  String get profileNoPhotos => 'No photos yet';

  @override
  String profilePhotosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get svcAsap => 'ASAP';

  @override
  String get svcStandard => 'Standard';

  @override
  String get svcAirport => 'Airport';

  @override
  String get statusOpen => 'Open';

  @override
  String get statusInProgress => 'In Progress';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusArchived => 'Archived';

  @override
  String get jobStatus => 'JOB STATUS';

  @override
  String get statusSummary => 'STATUS SUMMARY';

  @override
  String get statusSummarySubtitle => 'Full job lifecycle';

  @override
  String get statusTapHint => 'Tap any step to change the status';

  @override
  String get statusOpened => 'Opened';

  @override
  String get locationLabel => 'LOCATION';

  @override
  String get openInMaps => 'Open in Maps';

  @override
  String get copyCoords => 'Copy Coords';

  @override
  String get coordsCopied => 'Coordinates copied to clipboard';

  @override
  String get mapLinkCopied => 'Maps link copied — paste in your browser';

  @override
  String get noteLabel => 'Note';

  @override
  String get notePlaceholder => 'Add a note…';

  @override
  String get saveNote => 'Save Note';

  @override
  String get noteSaved => 'Note saved';

  @override
  String get addressLabel => 'Address & ZIP';

  @override
  String get saveAddress => 'Save Address';

  @override
  String get addressSaved => 'Address saved';

  @override
  String get addressAutoFill => 'Auto-fill';

  @override
  String get deletePhoto => 'Delete Photo';

  @override
  String get deleteConfirmTitle => 'Delete Photo';

  @override
  String get deleteConfirmBody =>
      'This photo will be permanently deleted. This action cannot be undone.';

  @override
  String get deleteConfirm => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get editPhoto => 'Edit Photo';

  @override
  String get replacePhoto => 'Replace Photo';

  @override
  String get replacePhotoSubtitle => 'Swap the image with a new one';

  @override
  String get photoUpdated => 'Photo updated successfully';

  @override
  String get photoDeleted => 'Photo deleted';

  @override
  String get editLocation => 'Edit Location';

  @override
  String get timestampUpdated => 'Timestamp updated';

  @override
  String get capturedLabel => 'Captured';

  @override
  String get payoutLabel => 'Payout';

  @override
  String get linkedProfiles => 'LINKED PROFILES';

  @override
  String get csvExportTitle => 'Export CSV';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get goBack => 'Go Back';

  @override
  String get photoNotFound => 'Photo not found';

  @override
  String get photoNotFoundSubtitle => 'This photo may have been deleted.';

  @override
  String get failedToLoadPhoto => 'Failed to load photo';

  @override
  String get couldNotLoadPhotos => 'Could not load photos';

  @override
  String get fetchingAddress => 'Fetching address…';

  @override
  String get locating => 'Locating…';

  @override
  String statusUpdatedTo(String status) {
    return 'Status updated to $status';
  }

  @override
  String get takeNewPhoto => 'Take a new photo';

  @override
  String get chooseFromGallery => 'Choose from gallery';
}
