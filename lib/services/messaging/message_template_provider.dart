import '../../models/message_template.dart';

/// Supplies a host's scheduled-message template for a trigger.
///
/// Implementations fall back to [MessageTemplate.defaultFor] when the host
/// hasn't customized anything, so callers always get a usable template and
/// check only [MessageTemplate.enabled].
abstract class MessageTemplateProvider {
  Future<MessageTemplate> templateFor(
    String hostId,
    MessageTemplateTrigger trigger,
  );

  /// The language a host sends automated guest messages in. Defaults to
  /// English when unset or unavailable.
  Future<MessageLanguage> languageFor(String hostId);
}

/// Provider used when no storage is wired: every host gets the defaults.
class DefaultMessageTemplateProvider implements MessageTemplateProvider {
  const DefaultMessageTemplateProvider();

  @override
  Future<MessageTemplate> templateFor(
    String hostId,
    MessageTemplateTrigger trigger,
  ) async {
    return MessageTemplate.defaultFor(hostId, trigger);
  }

  @override
  Future<MessageLanguage> languageFor(String hostId) async =>
      MessageLanguage.en;
}
