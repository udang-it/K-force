BigInt? parseKronTokenAmount(String input, int decimals) {
  if (decimals < 0 || decimals > 18) return null;
  final normalized = input.trim();
  if (normalized.isEmpty || !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) {
    return null;
  }
  final parts = normalized.split('.');
  if (parts.length == 2 && parts[1].length > decimals) return null;
  final scale = BigInt.from(10).pow(decimals);
  final whole = BigInt.tryParse(parts.first);
  final fraction = parts.length == 1
      ? BigInt.zero
      : BigInt.tryParse(parts[1].padRight(decimals, '0'));
  if (whole == null || fraction == null) return null;
  final amount = whole * scale + fraction;
  return amount > BigInt.zero ? amount : null;
}
