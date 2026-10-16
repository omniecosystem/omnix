import 'dart:convert';

final class OmnixCoreSamplingOptions {
  factory OmnixCoreSamplingOptions.fromJson(Map<String, dynamic> json) {
    final value = OmnixCoreSamplingOptions(
      temperature: (json['temperature'] as num).toDouble(),
      topK: json['top_k'] as int,
      topP: (json['top_p'] as num).toDouble(),
      seed: json['seed'] as int,
    );
    value.encode();
    return value;
  }
  const OmnixCoreSamplingOptions({
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
