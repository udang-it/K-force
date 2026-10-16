import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/src/kasdex_contract.dart';

void main() {
  test('KasDex v5 token branch script matches the protocol vector', () {
    expect(
      kasDexV5TokenBranchScript(
        ownerXOnlyPublicKey: Uint8List(32)..fillRange(0, 32, 1),
        amount: BigInt.from(1234),
      ),
      'aa20421920a3f825d1225218fe36d15027b018792b02e873d2ee2f83de4e934cad5787',
    );
  });

  test('KasDex token branch rejects invalid state', () {
    expect(
      () => kasDexV5TokenBranchScript(
        ownerXOnlyPublicKey: Uint8List(31),
        amount: BigInt.one,
      ),
      throwsArgumentError,
    );
  });
}
