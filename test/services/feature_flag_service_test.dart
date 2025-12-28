import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/feature_flag_service.dart';

/// Unit tests for Feature Flag Service (Transport Layer v1)
void main() {
  late FeatureFlagService service;

  setUp(() {
    service = FeatureFlagService();
  });

  group('Transport Layer Kill Switch', () {
    test('should be OFF by default (local-only mode)', () async {
      final enabled = await service.isTransportLayerEnabled();
      expect(enabled, isFalse);
    });
  });
}
