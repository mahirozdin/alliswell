import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/stt.dart';

/// R-10 (OPH-402): on a device with no audio input, `speech_to_text`'s listen
/// aborts the app natively (AudioToolbox RPC timeout, SIGABRT) about six
/// seconds in. Dart cannot catch that, so the controller must ask whether any
/// input exists first and never reach the plugin when the answer is no.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pluginChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');

  final pluginCalls = <String>[];
  setUp(() {
    pluginCalls.clear();
    messenger.setMockMethodCallHandler(pluginChannel, (call) async {
      pluginCalls.add(call.method);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(pluginChannel, null);
    messenger.setMockMethodCallHandler(audioInputChannel, null);
  });

  test(
    'no audio input: initialize says so and never touches the plugin',
    () async {
      final controller = SpeechToTextController(
        hasAudioInput: () async => false,
      );
      final init = await controller.initialize();
      expect(init.available, isFalse);
      expect(init.noMicrophone, isTrue);
      expect(pluginCalls, isEmpty);
    },
  );

  test('an unknown answer goes on to the plugin as before', () async {
    final controller = SpeechToTextController(hasAudioInput: () async => null);
    final init = await controller.initialize();
    expect(init.noMicrophone, isFalse);
    expect(pluginCalls, contains('initialize'));
  });

  test('the platform probe reads the iOS channel', () async {
    messenger.setMockMethodCallHandler(audioInputChannel, (call) async {
      expect(call.method, 'isInputAvailable');
      return false;
    });
    expect(await platformAudioInputAvailable(), isFalse);
  });

  test('no handler (Android, macOS, web): the probe answers null', () async {
    expect(await platformAudioInputAvailable(), isNull);
  });
}
