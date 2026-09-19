import 'package:flutter/material.dart';

Widget buildAdaptiveContextMenu(BuildContext context, EditableTextState editableTextState) {
  final List<ContextMenuButtonItem> buttonItems = List.from(editableTextState.contextMenuButtonItems);

  final text = editableTextState.textEditingValue.text;
  final selection = editableTextState.textEditingValue.selection;

  final bool hasPaste = buttonItems.any((item) => item.type == ContextMenuButtonType.paste);
  if (!hasPaste) {
    buttonItems.add(
      ContextMenuButtonItem(
        type: ContextMenuButtonType.paste,
        onPressed: () {
          editableTextState.pasteText(SelectionChangedCause.toolbar);
        },
      ),
    );
  }

  final bool hasSelectAll = buttonItems.any((item) => item.type == ContextMenuButtonType.selectAll);
  if (!hasSelectAll && text.isNotEmpty) {
    buttonItems.add(
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () {
          editableTextState.selectAll(SelectionChangedCause.toolbar);
        },
      ),
    );
  }

  final bool hasCopy = buttonItems.any((item) => item.type == ContextMenuButtonType.copy);
  if (!hasCopy && !selection.isCollapsed) {
    buttonItems.add(
      ContextMenuButtonItem(
        type: ContextMenuButtonType.copy,
        onPressed: () {
          editableTextState.copySelection(SelectionChangedCause.toolbar);
        },
      ),
    );
  }

  final bool hasCut = buttonItems.any((item) => item.type == ContextMenuButtonType.cut);
  if (!hasCut && !selection.isCollapsed) {
    buttonItems.add(
      ContextMenuButtonItem(
        type: ContextMenuButtonType.cut,
        onPressed: () {
          editableTextState.cutSelection(SelectionChangedCause.toolbar);
        },
      ),
    );
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: buttonItems,
  );
}
