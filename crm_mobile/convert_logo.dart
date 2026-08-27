import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final File file = File('assets/images/logo.webp');
  final bytes = file.readAsBytesSync();
  final image = img.decodeWebP(bytes);
  if (image != null) {
    File('assets/images/logo.png').writeAsBytesSync(img.encodePng(image));
    print('Successfully converted logo.webp to logo.png');
  } else {
    print('Failed to decode logo.webp');
  }
}
