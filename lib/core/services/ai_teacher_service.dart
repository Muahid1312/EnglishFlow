import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supported AI providers (Phase 1: configuration only).
enum AiProvider { none, openAi, anthropic, custom }

enum AiAvailability { unavailable, notConfigured, ready, error }

class AiStatus {
  final AiAvailability availability;
  final AiProvider provider;
  final String? message;

  const AiStatus({
    required this.availability,
    this.provider = AiProvider.none,
    this.message,
  });

  bool get isReady => availability == AiAvailability.ready;
}

/// Abstract interface — core app never depends on a live network call.
abstract class AiTeacherService {
  Future<AiStatus> checkStatus();
  Future<void> saveApiKey(AiProvider provider, String key);
  Future<void> clearCredentials();
  Future<AiProvider> getConfiguredProvider();
  Future<bool> hasCredentials();
}

class SecureAiTeacherService implements AiTeacherService {
  SecureAiTeacherService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _keyProvider = 'ai_provider';
  static const _keyApiKey = 'ai_api_key';

  @override
  Future<AiStatus> checkStatus() async {
    final providerName = await _storage.read(key: _keyProvider);
    final key = await _storage.read(key: _keyApiKey);

    if (providerName == null ||
        providerName == 'none' ||
        key == null ||
        key.isEmpty) {
      return const AiStatus(
        availability: AiAvailability.notConfigured,
        message: 'Configure an API key in Settings to enable AI Teacher.',
      );
    }

    final provider = _parseProvider(providerName);
    // Phase 1: we only verify that credentials exist. A real connectivity
    // ping would be added later and must never block offline startup.
    return AiStatus(
      availability: AiAvailability.ready,
      provider: provider,
      message: 'Credentials stored securely for ${provider.name}.',
    );
  }

  @override
  Future<void> saveApiKey(AiProvider provider, String key) async {
    if (key.trim().isEmpty) {
      await clearCredentials();
      return;
    }
    await _storage.write(key: _keyProvider, value: provider.name);
    await _storage.write(key: _keyApiKey, value: key.trim());
  }

  @override
  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyProvider);
    await _storage.delete(key: _keyApiKey);
  }

  @override
  Future<AiProvider> getConfiguredProvider() async {
    final name = await _storage.read(key: _keyProvider);
    return _parseProvider(name);
  }

  @override
  Future<bool> hasCredentials() async {
    final key = await _storage.read(key: _keyApiKey);
    return key != null && key.isNotEmpty;
  }

  AiProvider _parseProvider(String? name) {
    switch (name) {
      case 'openAi':
        return AiProvider.openAi;
      case 'anthropic':
        return AiProvider.anthropic;
      case 'custom':
        return AiProvider.custom;
      default:
        return AiProvider.none;
    }
  }
}

final aiTeacherServiceProvider = Provider<AiTeacherService>((ref) {
  return SecureAiTeacherService();
});
