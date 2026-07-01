// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Geo Tag';

  @override
  String get navHome => 'Inicio';

  @override
  String get navMap => 'Mapa';

  @override
  String get navEarnings => 'Ganancias';

  @override
  String get navLog => 'Registro';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get navUpload => 'Subir';

  @override
  String get loginTitle => 'Bienvenido de nuevo';

  @override
  String get loginSubtitle => 'Inicia sesión para continuar';

  @override
  String get loginButton => 'Iniciar sesión';

  @override
  String get logoutButton => 'Cerrar sesión';

  @override
  String get emailHint => 'Correo electrónico';

  @override
  String get passwordHint => 'Contraseña';

  @override
  String get uploadTitle => 'Subir foto';

  @override
  String get uploadSelectPhoto => 'Seleccionar foto';

  @override
  String get uploadCamera => 'Cámara';

  @override
  String get uploadGallery => 'Galería';

  @override
  String get uploadProfile => 'Perfil';

  @override
  String get uploadAddress => 'Dirección';

  @override
  String get uploadNote => 'Nota';

  @override
  String get uploadButton => 'Subir';

  @override
  String uploadingProgress(int current, int total) {
    return 'Subiendo $current de $total…';
  }

  @override
  String get uploadNewProfile => '+ Nuevo perfil';

  @override
  String get profileName => 'Nombre del perfil';

  @override
  String get profileCreate => 'Crear perfil';

  @override
  String get profilePrimaryAddress => 'Dirección principal';

  @override
  String get profileNoPhotos => 'Sin fotos aún';

  @override
  String profilePhotosCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fotos',
      one: '1 foto',
    );
    return '$_temp0';
  }

  @override
  String get svcAsap => 'Urgente';

  @override
  String get svcStandard => 'Estándar';

  @override
  String get svcAirport => 'Aeropuerto';

  @override
  String get statusOpen => 'Abierto';

  @override
  String get statusInProgress => 'En progreso';

  @override
  String get statusCompleted => 'Completado';

  @override
  String get statusArchived => 'Archivado';

  @override
  String get jobStatus => 'ESTADO DEL TRABAJO';

  @override
  String get statusSummary => 'RESUMEN DE ESTADO';

  @override
  String get statusSummarySubtitle => 'Ciclo completo del trabajo';

  @override
  String get statusTapHint => 'Toca cualquier paso para cambiar el estado';

  @override
  String get statusOpened => 'Abierto';

  @override
  String get locationLabel => 'UBICACIÓN';

  @override
  String get openInMaps => 'Abrir en mapas';

  @override
  String get copyCoords => 'Copiar coordenadas';

  @override
  String get coordsCopied => 'Coordenadas copiadas al portapapeles';

  @override
  String get mapLinkCopied =>
      'Enlace de mapas copiado — pégalo en el navegador';

  @override
  String get noteLabel => 'Nota';

  @override
  String get notePlaceholder => 'Añadir una nota…';

  @override
  String get saveNote => 'Guardar nota';

  @override
  String get noteSaved => 'Nota guardada';

  @override
  String get addressLabel => 'Dirección y código postal';

  @override
  String get saveAddress => 'Guardar dirección';

  @override
  String get addressSaved => 'Dirección guardada';

  @override
  String get addressAutoFill => 'Autocompletar';

  @override
  String get deletePhoto => 'Eliminar foto';

  @override
  String get deleteConfirmTitle => 'Eliminar foto';

  @override
  String get deleteConfirmBody =>
      'Esta foto se eliminará permanentemente. Esta acción no se puede deshacer.';

  @override
  String get deleteConfirm => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get editPhoto => 'Editar foto';

  @override
  String get replacePhoto => 'Reemplazar foto';

  @override
  String get replacePhotoSubtitle => 'Cambia la imagen por una nueva';

  @override
  String get photoUpdated => 'Foto actualizada correctamente';

  @override
  String get photoDeleted => 'Foto eliminada';

  @override
  String get editLocation => 'Editar ubicación';

  @override
  String get timestampUpdated => 'Marca de tiempo actualizada';

  @override
  String get capturedLabel => 'Capturada';

  @override
  String get payoutLabel => 'Pago';

  @override
  String get linkedProfiles => 'PERFILES VINCULADOS';

  @override
  String get csvExportTitle => 'Exportar CSV';

  @override
  String get tryAgain => 'Intentar de nuevo';

  @override
  String get goBack => 'Volver';

  @override
  String get photoNotFound => 'Foto no encontrada';

  @override
  String get photoNotFoundSubtitle =>
      'Es posible que esta foto haya sido eliminada.';

  @override
  String get failedToLoadPhoto => 'Error al cargar la foto';

  @override
  String get couldNotLoadPhotos => 'No se pudieron cargar las fotos';

  @override
  String get fetchingAddress => 'Obteniendo dirección…';

  @override
  String get locating => 'Localizando…';

  @override
  String statusUpdatedTo(String status) {
    return 'Estado actualizado a $status';
  }

  @override
  String get takeNewPhoto => 'Tomar una nueva foto';

  @override
  String get chooseFromGallery => 'Elegir de la galería';
}
