import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/services/ai_teacher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('configured client reports configuration without claiming connectivity',
      () async {
    final service = SecureAiTeacherService();
    expect((await service.checkStatus()).availability,
        AiAvailability.notConfigured);
    await service.saveApiKey(AiProvider.openAi, ' test-secret ');
    expect(await service.getConfiguredProvider(), AiProvider.openAi);
    final status = await service.checkStatus();
    expect(status.isReady, isTrue);
    expect(status.availability, AiAvailability.ready);
    expect(status.message, isNot(contains('test-secret')));
    await service.clearCredentials();
    expect(await service.hasCredentials(), isFalse);
  });

  test('none provider clears credentials instead of saving unusable key',
      () async {
    final service = SecureAiTeacherService();
    await service.saveApiKey(AiProvider.none, 'key');
    expect(await service.hasCredentials(), isFalse);
  });
}
