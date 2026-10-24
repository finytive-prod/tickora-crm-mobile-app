import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/blocs/settings_bloc.dart';
import 'package:crm_mobile/blocs/settings_event.dart';
import 'package:crm_mobile/blocs/settings_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';
import 'package:crm_mobile/widgets/confirmation_dialog.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';

class LeadStatusesScreen extends StatelessWidget {
  const LeadStatusesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<SettingsBloc>()..add(FetchLeadStatuses()),
      child: const LeadStatusesView(),
    );
  }
}

class LeadStatusesView extends StatefulWidget {
  const LeadStatusesView({super.key});

  @override
  State<LeadStatusesView> createState() => _LeadStatusesViewState();
}

class _LeadStatusesViewState extends State<LeadStatusesView> {
  bool _isLocalLoading = false;
  String? _errorMessage;
  List<LeadStatus> _statuses = [];
  bool _hasLoadedData = false;
  final ScrollController _scrollController = ScrollController();

  // Form states for creating status
  final _formKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  final _nameController = TextEditingController();
  final _orderController = TextEditingController(text: '1');
  bool _isDefault = false;
  String _selectedColor = '#3B82F6'; // Default color Blue

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    }
    return Colors.grey;
  }

  void _createStatus(BuildContext context) {
    if (!validateAndScrollToError(_formKey)) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }

    final newStatusName = _nameController.text.trim();
    final nextOrder = int.tryParse(_orderController.text) ?? (_statuses.length + 1);

    final statusData = {
      'statusName': newStatusName,
      'displayOrder': nextOrder,
      'color': _selectedColor,
      'isDefault': _isDefault,
      'automationLink': null,
      'isClosed': false,
    };

    context.read<SettingsBloc>().add(CreateLeadStatus(statusData));
  }

  Future<void> _deleteStatus(LeadStatus status) async {
    if (status.level == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stage 1 status is fixed and cannot be deleted.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (status.level == 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stage 3 status is managed by the system and cannot be deleted.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Delete Status',
      message: 'Are you sure you want to delete status "${status.statusName}"?',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed != true) return;

    setState(() {
      _isLocalLoading = true;
    });

    // Mock API delay
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _isLocalLoading = false;
        _statuses.removeWhere((s) => s.id == status.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status "${status.statusName}" deleted successfully!'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listener: (context, state) {
        if (state is LeadStatusesLoaded) {
          _statuses = List.from(state.statuses);
          _statuses.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          _hasLoadedData = true;
          _isLocalLoading = false;
          _orderController.text = (_statuses.length + 1).toString();
        } else if (state is LeadStatusCreated) {
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Status created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Reset form
          _nameController.clear();
          _isDefault = false;
          _selectedColor = '#3B82F6';
          context.read<SettingsBloc>().add(FetchLeadStatuses());
        } else if (state is LeadStatusReordered) {
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Status order updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          context.read<SettingsBloc>().add(FetchLeadStatuses());
        } else if (state is DefaultLeadStatusSet) {
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Default status updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          context.read<SettingsBloc>().add(FetchLeadStatuses());
        } else if (state is SettingsError) {
          _errorMessage = state.message;
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.primary,
            ),
          );
        } else if (state is SettingsLoading) {
          _isLocalLoading = true;
        }
      },
      builder: (context, state) {
        final showLoader = state is SettingsLoading && !_hasLoadedData;

        return Scaffold(
          backgroundColor: AppColors.secondary,
          appBar: AppBar(
            backgroundColor: AppColors.secondary,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Lead Statuses',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
                tooltip: 'Refresh Statuses',
                onPressed: () => context.read<SettingsBloc>().add(FetchLeadStatuses()),
              ),
            ],
          ),
          body: showLoader
              ? const Center(child: SpinningLogo(size: 60))
              : SafeArea(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (state is SettingsLoading && _hasLoadedData)
                          const LinearProgressIndicator(color: AppColors.primary),
                        // Subtitle Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Configured Lead Statuses',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Drag & drop items to reorder. Tap star to set default.',
                                style: TextStyle(color: AppColors.textHint, fontSize: 12),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ]
                            ],
                          ),
                        ),

                        // Reorderable List of current statuses
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.borderEnabled),
                          ),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _statuses.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (_isLocalLoading) return;
                              final item = _statuses[oldIndex];
                              var targetIdx = newIndex;
                              if (targetIdx > oldIndex) {
                                targetIdx -= 1;
                              }
                              if (oldIndex == targetIdx) return;

                              // Stage 1 (level 1) is fixed at the first position
                              if (item.level == 1 || targetIdx == 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Stage 1 status is fixed at the first position and cannot be changed.'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              final targetItem = _statuses[targetIdx];
                              // Moving from Stage 3 to Stage 1 check
                              if (item.level == 3 && targetItem.level == 1) {
                                final isAdmin = sl<PrivilegeService>().isAdminOrSuperAdmin();
                                if (!isAdmin) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Only Admin and Super Admin can move a status from Stage 3 to Stage 1.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                final confirmed = await ConfirmationDialog.show(
                                  context,
                                  title: 'Confirm Status Reorder',
                                  message: 'Are you sure you want to move "${item.statusName}" from Stage 3 to Stage 1?',
                                  confirmLabel: 'Move',
                                  isDestructive: false,
                                );
                                if (confirmed != true) return;
                              }

                              setState(() {
                                final moved = _statuses.removeAt(oldIndex);
                                _statuses.insert(targetIdx, moved);

                                // Trigger PATCH reorder API
                                context.read<SettingsBloc>().add(
                                      ReorderLeadStatus(moved.id, targetIdx + 1),
                                    );
                              });

                              // Automatically scroll the screen back up to top after drag/reorder
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (_scrollController.hasClients) {
                                  _scrollController.animateTo(
                                    0,
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeOutCubic,
                                  );
                                }
                              });
                            },
                            itemBuilder: (context, index) {
                              final status = _statuses[index];
                              final color = _hexToColor(status.color);
                              final isStage1 = status.level == 1;
                              final isStage3 = status.level == 3;

                              final String stageText = isStage1
                                  ? 'Stage 1 (Fixed)'
                                  : isStage3
                                      ? 'Stage 3 (Closed)'
                                      : 'Stage 2 (Customizable)';
                              final Color stageBg = isStage1
                                  ? const Color(0xFFEFF6FF)
                                  : isStage3
                                      ? const Color(0xFFFEF2F2)
                                      : const Color(0xFFF5F3FF);
                              final Color stageColor = isStage1
                                  ? const Color(0xFF2563EB)
                                  : isStage3
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF7C3AED);

                              return ListTile(
                                key: ValueKey(status.id),
                                leading: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        status.statusName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: stageBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        stageText,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: stageColor),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  'Order: ${status.displayOrder}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: (_isLocalLoading || isStage1)
                                          ? null
                                          : () {
                                              context
                                                  .read<SettingsBloc>()
                                                  .add(SetDefaultLeadStatus(status.id));
                                            },
                                      child: status.isDefault
                                          ? const Icon(Icons.star, color: Colors.amber, size: 22)
                                          : (isStage1 ? const SizedBox(width: 22) : const Icon(Icons.star_border, color: Colors.grey, size: 22)),
                                    ),
                                    const SizedBox(width: 16),
                                    if (!isStage1 && !isStage3)
                                      GestureDetector(
                                        onTap: _isLocalLoading ? null : () => _deleteStatus(status),
                                        child: const Icon(Icons.delete_outline, color: AppColors.primary, size: 20),
                                      )
                                    else
                                      const SizedBox(width: 20),
                                    const SizedBox(width: 12),
                                    if (!isStage1)
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
                                      )
                                    else
                                      const SizedBox(width: 20),
                                  ],
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Create Lead Status Form Section (White card)
                        Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.borderEnabled),
                          ),
                          child: Form(
                            key: _formKey,
                            autovalidateMode: _autovalidateMode,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Create Lead Status',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Status Name
                                TextFormField(
                                  controller: _nameController,
                                  enabled: !_isLocalLoading,
                                  decoration: const InputDecoration(
                                    labelText: 'Status Name',
                                    hintText: 'e.g. Lead Discovered',
                                    labelStyle: TextStyle(color: AppColors.textLabel),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Status Name is required';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Color Palette Selector
                                const Text(
                                  'Status Palette Color',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textLabel),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: _isLocalLoading ? null : () {
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: const Text('Pick a color'),
                                          content: SingleChildScrollView(
                                            child: ColorPicker(
                                              pickerColor: _hexToColor(_selectedColor),
                                              onColorChanged: (color) {
                                                setState(() {
                                                  _selectedColor = '#${color.value.toRadixString(16).substring(2, 8).toUpperCase()}';
                                                });
                                              },
                                              pickerAreaHeightPercent: 0.8,
                                              enableAlpha: false,
                                              displayThumbColor: true,
                                            ),
                                          ),
                                          actions: <Widget>[
                                            TextButton(
                                              child: const Text('Done'),
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: _hexToColor(_selectedColor),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.borderEnabled, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                                color: _hexToColor(_selectedColor).withOpacity(0.4),
                                                blurRadius: 6,
                                                spreadRadius: 1)
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      const Text(
                                        'Tap to pick any color',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Sort Order Input
                                TextFormField(
                                  controller: _orderController,
                                  enabled: !_isLocalLoading,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Display Order',
                                    hintText: 'e.g. 5',
                                    labelStyle: TextStyle(color: AppColors.textLabel),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Display Order is required';
                                    if (int.tryParse(val) == null) return 'Must be a valid integer';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),

                                // Default Status Switch
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Set as Default Status',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textLabel),
                                    ),
                                    Switch(
                                      value: _isDefault,
                                      activeColor: AppColors.primary,
                                      onChanged: _isLocalLoading ? null : (val) {
                                        setState(() {
                                          _isDefault = val;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

                                // Submit Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLocalLoading ? null : () => _createStatus(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    child: const Text('Create Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
