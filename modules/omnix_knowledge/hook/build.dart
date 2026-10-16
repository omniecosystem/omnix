import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'android_toolchain.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final stores = input.userDefines['stores'];
    if (stores is! List || stores.length != 1 || stores.single != 'qdrant') {
      throw ArgumentError(
        'Select omnix_knowledge.stores: [qdrant] explicitly.',
      );
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      enableDefaultFeatures: false,
      features: ['qdrant'],
      extraCargoEnvironmentVariables: androidToolchainEnvironment(
        input.config.code,
      ),
    ).run(input: input, output: output);
  });
}
