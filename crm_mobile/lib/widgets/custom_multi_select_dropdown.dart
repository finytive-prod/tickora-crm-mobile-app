import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';

class CustomMultiSelectDropdown<T> extends StatefulWidget {
  final String label;
  final bool isRequired;
  final List<T> items;
  final List<T> selectedItems;
  final String Function(T) itemLabelBuilder;
  final void Function(List<T>) onChanged;

  const CustomMultiSelectDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.selectedItems,
    required this.itemLabelBuilder,
    required this.onChanged,
    this.isRequired = false,
  });

  @override
  State<CustomMultiSelectDropdown<T>> createState() => _CustomMultiSelectDropdownState<T>();
}

class _CustomMultiSelectDropdownState<T> extends State<CustomMultiSelectDropdown<T>> {
  
  void _showMultiSelectDialog(BuildContext context) async {
    final List<T> currentSelections = List.from(widget.selectedItems);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text('Select ${widget.label}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.items.map((item) {
                    final isSelected = currentSelections.contains(item);
                    return CheckboxListTile(
                      activeColor: AppColors.primary,
                      title: Text(widget.itemLabelBuilder(item)),
                      value: isSelected,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            currentSelections.add(item);
                          } else {
                            currentSelections.remove(item);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onChanged(currentSelections);
                  },
                  child: const Text('Done', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String displayText = 'Select ${widget.label}';
    if (widget.selectedItems.isNotEmpty) {
      if (widget.selectedItems.length == 1) {
        displayText = widget.itemLabelBuilder(widget.selectedItems.first);
      } else {
        displayText = '${widget.selectedItems.length} selected';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: RichText(
            text: TextSpan(
              text: widget.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textLabel,
              ),
              children: [
                if (widget.isRequired)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Color(0xFF111827)),
                  ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () => _showMultiSelectDialog(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderEnabled),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    displayText,
                    style: TextStyle(
                      color: widget.selectedItems.isEmpty ? AppColors.textHint : AppColors.textPrimary,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, color: AppColors.textHint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
