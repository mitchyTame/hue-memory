import 'dart:typed_data';

import 'mistral_ocr_client.dart';
import 'mock_ocr_client.dart';
import 'ocr_client.dart';
import 'ocr_settings.dart';

/// Picks live Mistral vs mock per [OcrSettingsStore] on each call.
class ConfigurableOcrClient implements OcrClient {
  ConfigurableOcrClient({
    required this.settings,
    OcrClient? mock,
    MistralOcrClient Function(String apiKey)? mistralFactory,
  })  : mock = mock ?? MockOcrClient(),
        mistralFactory = mistralFactory ??
            ((key) => MistralOcrClient(apiKey: key));

  final OcrSettingsStore settings;
  final OcrClient mock;
  final MistralOcrClient Function(String apiKey) mistralFactory;

  @override
  Future<MeaningResult> extractMeaning(Uint8List imageBytes) async {
    final cfg = await settings.read();
    if (cfg.shouldUseLive) {
      return mistralFactory(cfg.apiKey).extractMeaning(imageBytes);
    }
    return mock.extractMeaning(imageBytes);
  }
}
