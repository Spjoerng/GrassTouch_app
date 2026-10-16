import 'dart:io';
import 'package:image/image.dart' as image;

/// Keep the supplied transparent artwork untouched. Produce an opaque master
/// for platforms that do not provide a separate launcher background layer.
void main() {
  final source = image.decodePng(File('assets/icon.png').readAsBytesSync());
  if (source == null) throw const FormatException('Invalid assets/icon.png');
  final artwork = image.copyResize(
    source,
    width: 1024,
    height: 1024,
    interpolation: image.Interpolation.cubic,
  );
  final master = image.Image(width: 1024, height: 1024, numChannels: 3);
  image.fill(master, color: image.ColorRgb8(0x25, 0x4f, 0x40));
  image.compositeImage(master, artwork);
  File('assets/launcher_icon.png').writeAsBytesSync(image.encodePng(master));
}
