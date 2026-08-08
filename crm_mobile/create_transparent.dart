import 'dart:io';
import 'dart:convert';

void main() {
  final bytes = base64Decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==");
  File('assets/images/transparent.png').writeAsBytesSync(bytes);
}
