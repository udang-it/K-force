import 'package:flutter_test/flutter_test.dart';
import 'package:k_force/src/kron_trade_amount.dart';

void main() {
  test('parses token amounts without floating-point rounding', () {
    expect(parseKronTokenAmount('12.34', 2), BigInt.from(1234));
    expect(parseKronTokenAmount('0.000001', 6), BigInt.one);
    expect(parseKronTokenAmount('20', 0), BigInt.from(20));
    expect(parseKronTokenAmount('1.001', 2), isNull);
    expect(parseKronTokenAmount('1e3', 2), isNull);
    expect(parseKronTokenAmount('0', 8), isNull);
  });
}
