import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'component_selection.dart';
import 'android_toolchain.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final features = selectStorageFeatures({
      'engines': input.userDefines['engines'],
    });
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      enableDefaultFeatures: false,
      features: features,
      extraCargoEnvironmentVariables: androidToolchainEnvironment(
        input.config.code,
      ),
    ).run(input: input, output: output);
  });
}
