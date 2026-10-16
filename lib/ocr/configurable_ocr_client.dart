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

  /// Why live OCR is off — for UI feedback (never silent).
  Future<String?> liveBlockedReason() async {
    final cfg = await settings.read();
    if (cfg.shouldUseLive) return null;
    if (!cfg.useLive) {
      return 'Live Mistral OCR is off — enable it in Settings → OCR';
    }
    if (!cfg.consentGiven) {
      return 'Consent required before photos can go to Mistral';
    }
    if (cfg.apiKey.trim().isEmpty) {
      return 'No Mistral API key — add one in Settings → OCR';
    }
    return 'Mock OCR is active';
  }

  Future<MistralConnectionResult> verifyLiveKey(String apiKey) {
    return mistralFactory(apiKey.trim()).verifyConnection();
  }

  @override
  Future<MeaningResult> extractMeaning(
    Uint8List imageBytes, {
    String? imageMimeType,
    String? extensionHint,
    bool allowEmpty = false,
  }) async {
    final cfg = await settings.read();
    if (cfg.shouldUseLive) {
      return mistralFactory(cfg.apiKey).extractMeaning(
        imageBytes,
        imageMimeType: imageMimeType,
        extensionHint: extensionHint,
        allowEmpty: allowEmpty,
      );
    }
    return mock.extractMeaning(
      imageBytes,
      imageMimeType: imageMimeType,
      extensionHint: extensionHint,
      allowEmpty: allowEmpty,
    );
  }
}
