import 'dart:convert';

final class OmnixSamplingOptions {
  const OmnixSamplingOptions({
    this.temperature = 0.8,
    this.topK = 40,
    this.topP = 0.95,
    this.seed = 0,
  });
  final double temperature;
  final int topK;
  final double topP;
  final int seed;
  String encode() {
    if (!temperature.isFinite ||
        temperature < 0 ||
        temperature > 2 ||
        topK < 1 ||
        topK > 10000 ||
        !topP.isFinite ||
        topP <= 0 ||
        topP > 1 ||
        seed < 0 ||
        seed > 0x7fffffff) {
      throw ArgumentError('Invalid sampling configuration.');
    }
    return jsonEncode({
      'temperature': temperature,
      'top_k': topK,
      'top_p': topP,
      'seed': seed,
    });
  }
}
