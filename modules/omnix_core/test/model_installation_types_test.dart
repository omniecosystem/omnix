import 'dart:convert';

import 'package:omnix_core/model_installation_types.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reservation roundtrip preserves identity and contains no credentials',
    () {
      const reservation = OmnixTransferReservation(
        id: 'a-123-1',
        path: '/app/models/.transfer-a-123-1/model.litertlm',
        spec: OmnixModelSpec(
          filename: 'model.litertlm',
          sha256: 'trusted-hash',
          bytes: 165000000,
          role: 'embedding',
        ),
      );
      final json =
          jsonDecode(jsonEncode(reservation.toJson())) as Map<String, dynamic>;
      final restored = OmnixTransferReservation.fromJson(json);
      expect(restored.id, reservation.id);
      expect(restored.path, reservation.path);
      expect(restored.spec.toJson(), reservation.spec.toJson());
      expect(json.keys, unorderedEquals(['id', 'spec', 'path']));
    },
  );

  test('malformed reservation is not silently accepted', () {
    expect(
      () => OmnixTransferReservation.fromJson({'id': 123}),
      throwsA(isA<TypeError>()),
    );
  });
}
