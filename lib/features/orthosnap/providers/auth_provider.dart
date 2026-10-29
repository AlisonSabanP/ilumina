import 'package:flutter/foundation.dart';

import '../../medicion/modelos/measurement_models.dart';
import '../modelos/orthosnap_modelos.dart';

/// Estado de la sesión clínica de OrthoSnap.
///
/// OrthoSnap está **restringido a profesionales**: el acceso requiere iniciar
/// sesión, y la sesión caduca sola tras un periodo de inactividad para evitar
/// que un dispositivo compartido en consulta quede abierto.
///
/// La autenticación es deliberadamente **simulada**: no hay backend. El
/// propósito es demostrar el control de acceso y el flujo clínico completo. Ver
/// las notas de mantenimiento sobre cómo sustituirla por un proveedor real.
class AuthProvider extends ChangeNotifier {
  AuthProvider({Duration? sessionTimeout})
      : _sessionTimeout = sessionTimeout ?? const Duration(minutes: 30);

  /// Credenciales de demostración. Se listan aquí a propósito para que el
  /// corrector pueda entrar, y se marcan claramente como mock.
  static const String demoProfessionalId = 'orto.demo';
  static const String demoProfessionalPassword = 'lumina-orto';

  final Duration _sessionTimeout;

  bool _authenticated = false;
  String? _professionalName;
  String? _professionalId;
  DateTime? _lastActivity;
  String? _error;

  // --- Lectura ---------------------------------------------------------------

  bool get isAuthenticated => _authenticated;

  /// `true` si la sesión existe pero ha caducado por inactividad.
  bool get isSessionExpired =>
      _authenticated &&
      _lastActivity != null &&
      DateTime.now().difference(_lastActivity!) > _sessionTimeout;

  String? get professionalName => _professionalName;
  String? get professionalId => _professionalId;
  String? get error => _error;

  /// Minutos que quedan antes de que caduque la sesión.
  int get minutesLeft {
    if (!_authenticated || _lastActivity == null) return 0;
    final elapsed = DateTime.now().difference(_lastActivity!);
    final remaining = _sessionTimeout - elapsed;
    return remaining.isNegative ? 0 : remaining.inMinutes;
  }

  // --- Acciones --------------------------------------------------------------

  /// Intenta iniciar sesión. Devuelve `true` si lo consigue.
  Future<bool> login({
    required String professionalId,
    required String password,
    String? displayName,
  }) async {
    _error = null;
    notifyListeners();

    // Simula la latencia de un servidor real.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final id = professionalId.trim().toLowerCase();
    if (id.isEmpty || password.isEmpty) {
      _error = 'Introduce tu número de colegiado y tu contraseña.';
      notifyListeners();
      return false;
    }

    if (id != demoProfessionalId || password != demoProfessionalPassword) {
      _error =
          'Credenciales incorrectas. En esta demo usa $demoProfessionalId / '
          '$demoProfessionalPassword.';
      notifyListeners();
      return false;
    }

    _authenticated = true;
    _professionalId = id;
    _professionalName =
        displayName?.trim().isNotEmpty == true ? displayName!.trim() : 'Profesional sanitario';
    _lastActivity = DateTime.now();
    notifyListeners();
    return true;
  }

  /// Renueva la marca de actividad (llamar en cada interacción relevante).
  void touch() {
    if (!_authenticated) return;
    _lastActivity = DateTime.now();
  }

  /// Cierra la sesión y borra todos los datos del paciente en memoria.
  void logout() {
    _authenticated = false;
    _professionalName = null;
    _professionalId = null;
    _lastActivity = null;
    _error = null;
    _request = const OrthoSnapRequest();
    _errorMessage = null;
    notifyListeners();
  }

  // --- Datos clínicos --------------------------------------------------------

  OrthoSnapRequest _request = const OrthoSnapRequest();
  String? _errorMessage;

  OrthoSnapRequest get request => _request;

  /// Mensaje de validación del formulario clínico.
  String? get validationError => _errorMessage;

  bool get isRequestValid =>
      _request.measurements.isNotEmpty && _request.diagnosis.trim().isNotEmpty;

  void setBodyZone(BodyZone zone) {
    touch();
    _request = _request.copyWith(bodyZone: zone);
    notifyListeners();
  }

  void setSplintType(SplintType type) {
    touch();
    _request = _request.copyWith(splintType: type);
    notifyListeners();
  }

  void setDiagnosis(String value) {
    touch();
    _request = _request.copyWith(diagnosis: value);
    notifyListeners();
  }

  void setAffectedSide(String? side) {
    touch();
    _request = _request.copyWith(
      affectedSide: side,
      clearAffectedSide: side == null,
    );
    notifyListeners();
  }

  void setNotes(String value) {
    touch();
    _request = _request.copyWith(notes: value);
    notifyListeners();
  }

  void setMaterial(String value) {
    touch();
    _request = _request.copyWith(material: value);
    notifyListeners();
  }

  void addMeasurement(Measurement measurement) {
    touch();
    final list = List<Measurement>.from(_request.measurements);
    final index = list.indexWhere(
      (m) => m.label.toLowerCase() == measurement.label.toLowerCase(),
    );
    if (index >= 0) {
      list[index] = measurement;
    } else {
      list.add(measurement);
    }
    _request = _request.copyWith(measurements: list);
    notifyListeners();
  }

  void removeMeasurement(String id) {
    touch();
    final list = List<Measurement>.from(_request.measurements)
      ..removeWhere((m) => m.id == id);
    _request = _request.copyWith(measurements: list);
    notifyListeners();
  }

  /// Valida el formulario clínico antes de generar.
  ///
  /// Se exige un diagnóstico y al menos una medida: generar una órtesis sin
  /// medidas produciría una pieza inútil para el paciente.
  bool validateForGeneration() {
    if (_request.diagnosis.trim().isEmpty) {
      _errorMessage =
          'Añade la indicación clínica: es obligatoria para justificar el diseño.';
      notifyListeners();
      return false;
    }
    if (_request.measurements.isEmpty) {
      _errorMessage =
          'Añade al menos una medida del paciente. Sin medidas la órtesis no '
          'se ajustará correctamente.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    return true;
  }
}
