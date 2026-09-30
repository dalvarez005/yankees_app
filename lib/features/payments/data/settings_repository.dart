import '../../../core/network/api_client.dart';
import 'payment_models.dart';
import 'payments_repository.dart';

/// Configuración de pagos (docs/API_PAGOS.md §3.3). Cualquier usuario con
/// sesión la lee (p. ej. el WhatsApp de contacto); editarla requiere
/// `configuracion.gestionar`.
abstract class SettingsRepository {
  static SettingsRepository instance = MockSettingsRepository();

  Future<PaymentSettings> paymentSettings();
  Future<PaymentSettings> updatePaymentSettings(PaymentSettings settings);
}

class ApiSettingsRepository implements SettingsRepository {
  ApiSettingsRepository(this._api);
  final ApiClient _api;

  static const _base = '/api/Settings';

  @override
  Future<PaymentSettings> paymentSettings() async =>
      _parse(await _call(() => _api.get('$_base/GetPaymentSettings')));

  @override
  Future<PaymentSettings> updatePaymentSettings(
    PaymentSettings settings,
  ) async {
    final json = await _call(
      () => _api.post('$_base/UpdatePaymentSettings', settings.toJson()),
    );
    // Si la API no devuelve el objeto, lo guardado es lo enviado.
    return json['settingsData'] is Map<String, dynamic>
        ? _parse(json)
        : settings;
  }

  static PaymentSettings _parse(Map<String, dynamic> json) =>
      PaymentSettings.fromJson(
        json['settingsData'] as Map<String, dynamic>? ?? const {},
      );

  Future<Map<String, dynamic>> _call(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    try {
      return await request();
    } on ApiException catch (e) {
      throw PaymentsException(e.message);
    }
  }
}

class MockSettingsRepository implements SettingsRepository {
  MockSettingsRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  var _settings = const PaymentSettings(
    defaultEnrollmentFee: 250,
    defaultMonthlyFee: 150,
    whatsappNumber: '50200000000',
    contactName: 'Tesorería del club',
  );

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  @override
  Future<PaymentSettings> paymentSettings() async {
    await _wait();
    return _settings;
  }

  @override
  Future<PaymentSettings> updatePaymentSettings(
    PaymentSettings settings,
  ) async {
    await _wait();
    if (settings.dueDay < 1 || settings.dueDay > 28) {
      throw const PaymentsException('El día límite debe estar entre 1 y 28.');
    }
    return _settings = settings;
  }
}
