import '../../config/sms_config.dart';
import 'alpha_sms_gateway.dart';
import 'bulk_sms_bd_gateway.dart';
import 'console_sms_gateway.dart';
import 'sms_gateway.dart';
import 'zaman_it_sms_gateway.dart';

/// Factory for creating SMS gateways based on configuration
class SmsGatewayFactory {
  SmsGatewayFactory._();

  static SmsGateway? _instance;

  /// Get the SMS gateway based on current configuration
  static SmsGateway getGateway() {
    _instance ??= _createGateway();
    return _instance!;
  }

  static SmsGateway _createGateway() {
    switch (SmsConfig.activeProvider) {
      case SmsProvider.console:
        return ConsoleSmsGateway();
      case SmsProvider.bulkSmsBd:
        return BulkSmsBdGateway();
      case SmsProvider.alphaSms:
        return AlphaSmsGateway();
      case SmsProvider.zamanIt:
        return ZamanItSmsGateway();
    }
  }

  /// Reset the gateway instance (useful for testing)
  static void reset() {
    _instance = null;
  }
}
