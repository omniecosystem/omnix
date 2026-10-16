import 'dart:typed_data';
import 'rust/api/input.dart' as native;

enum OmnixInteractionInputKind { text, image, audio }

final class OmnixInteractionInput {
  OmnixInteractionInput.text(String value)
    : kind = OmnixInteractionInputKind.text,
      text = value,
      bytes = Uint8List(0).asUnmodifiableView();
  OmnixInteractionInput.image(Uint8List value)
    : kind = OmnixInteractionInputKind.image,
      text = null,
      bytes = Uint8List.fromList(value).asUnmodifiableView();
  OmnixInteractionInput.audio(Uint8List value)
    : kind = OmnixInteractionInputKind.audio,
      text = null,
      bytes = Uint8List.fromList(value).asUnmodifiableView();
  final OmnixInteractionInputKind kind;
  final String? text;
  final Uint8List bytes;
}

List<native.InteractionInputPart> nativeInteractionParts(
  List<OmnixInteractionInput> parts,
) => [
  for (final part in parts)
    native.InteractionInputPart(
      kind: native.InteractionInputKind.values[part.kind.index],
      text: part.text,
      bytes: part.bytes,
    ),
];
