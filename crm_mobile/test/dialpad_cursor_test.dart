import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dialer cursor insertion and backspace logic', () {
    final controller = TextEditingController(text: '9090909090');

    // Simulate placing cursor at index 3: "909|0909090"
    controller.selection = const TextSelection.collapsed(offset: 3);

    // Insert '5' at cursor position
    final text = controller.text;
    final selection = controller.selection;
    int start = selection.start >= 0 ? selection.start : text.length;
    int end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.replaceRange(start, end, '5');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );

    expect(controller.text, equals('90950909090'));
    expect(controller.selection.baseOffset, equals(4));

    // Delete at cursor position
    final text2 = controller.text;
    final selection2 = controller.selection;
    int start2 = selection2.start >= 0 ? selection2.start : text2.length;
    int end2 = selection2.end >= 0 ? selection2.end : text2.length;

    final newText2 = text2.replaceRange(start2 - 1, start2, '');
    controller.value = TextEditingValue(
      text: newText2,
      selection: TextSelection.collapsed(offset: start2 - 1),
    );

    expect(controller.text, equals('9090909090'));
    expect(controller.selection.baseOffset, equals(3));
  });
}
