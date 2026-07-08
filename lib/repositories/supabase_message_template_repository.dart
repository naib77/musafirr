import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_template.dart';
import '../services/messaging/message_template_provider.dart';

/// Stores a host's scheduled-message templates in Supabase.
///
/// A row exists only once the host customizes (or disables) a trigger;
/// otherwise [MessageTemplate.defaultFor] applies, so every host has working
/// scheduled messages out of the box.
class SupabaseMessageTemplateRepository implements MessageTemplateProvider {
  SupabaseMessageTemplateRepository._();

  static SupabaseMessageTemplateRepository? _instance;
  static SupabaseMessageTemplateRepository get instance {
    _instance ??= SupabaseMessageTemplateRepository._();
    return _instance!;
  }

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<MessageTemplate> templateFor(
    String hostId,
    MessageTemplateTrigger trigger,
  ) async {
    try {
      final row = await _client
          .from('message_templates')
          .select()
          .eq('host_id', hostId)
          .eq('trigger', trigger.toJsonValue())
          .maybeSingle();

      if (row != null) return MessageTemplate.fromJson(row);
    } catch (e) {
      debugPrint('[MessageTemplateRepository] templateFor error: $e');
    }
    return MessageTemplate.defaultFor(hostId, trigger);
  }

  /// All three triggers for the editor screen, stored rows merged over
  /// defaults.
  Future<List<MessageTemplate>> templatesFor(String hostId) async {
    final stored = <MessageTemplateTrigger, MessageTemplate>{};
    try {
      final rows = await _client
          .from('message_templates')
          .select()
          .eq('host_id', hostId);
      for (final row in rows as List) {
        final template =
            MessageTemplate.fromJson(row as Map<String, dynamic>);
        stored[template.trigger] = template;
      }
    } catch (e) {
      debugPrint('[MessageTemplateRepository] templatesFor error: $e');
    }

    return [
      for (final trigger in MessageTemplateTrigger.values)
        stored[trigger] ?? MessageTemplate.defaultFor(hostId, trigger),
    ];
  }

  @override
  Future<MessageLanguage> languageFor(String hostId) async {
    try {
      // hostId may not be the caller → public_profiles view (migration 061).
      final row = await _client
          .from('public_profiles')
          .select('message_language')
          .eq('id', hostId)
          .maybeSingle();
      return MessageLanguage.fromString(row?['message_language'] as String?);
    } catch (e) {
      debugPrint('[MessageTemplateRepository] languageFor error: $e');
      return MessageLanguage.en;
    }
  }

  /// Sets the host's automated-message language on their profile.
  Future<bool> setLanguage(String hostId, MessageLanguage language) async {
    try {
      await _client
          .from('profiles')
          .update({'message_language': language.toJsonValue()}).eq(
              'id', hostId);
      return true;
    } catch (e) {
      debugPrint('[MessageTemplateRepository] setLanguage error: $e');
      return false;
    }
  }

  /// Saves the host's customization for one trigger.
  Future<bool> save(MessageTemplate template) async {
    try {
      await _client.from('message_templates').upsert(
            template.toJson(),
            onConflict: 'host_id,trigger',
          );
      return true;
    } catch (e) {
      debugPrint('[MessageTemplateRepository] save error: $e');
      return false;
    }
  }
}
