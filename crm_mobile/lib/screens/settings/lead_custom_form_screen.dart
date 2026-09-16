import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/blocs/settings_bloc.dart';
import 'package:crm_mobile/blocs/settings_event.dart';
import 'package:crm_mobile/blocs/settings_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';

class LeadCustomFormScreen extends StatelessWidget {
  const LeadCustomFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<SettingsBloc>()..add(FetchCustomFields()),
      child: const LeadCustomFormView(),
    );
  }
}

class LeadCustomFormView extends StatefulWidget {
  const LeadCustomFormView({super.key});

  @override
  State<LeadCustomFormView> createState() => _LeadCustomFormViewState();
}

class _LeadCustomFormViewState extends State<LeadCustomFormView> {
  bool _isLocalLoading = false;
  String? _errorMessage;
  List<CustomFieldConfig> _fields = [];
  List<String> _fieldTypes = [];
  bool _hasLoadedData = false;

  // Track async save actions
  bool _isSavingNew = false;
  bool _isUpdatingExisting = false;

  void _addNewRow() {
    setState(() {
      final nextOrder = _fields.isEmpty ? 1 : (_fields.map((f) => f.displayOrder).reduce((a, b) => a > b ? a : b) + 1);
      final defaultType = _fieldTypes.contains('TEXT') ? 'TEXT' : (_fieldTypes.isNotEmpty ? _fieldTypes.first : 'TEXT');
      _fields.add(CustomFieldConfig(
        label: '',
        type: defaultType,
        displayOrder: nextOrder,
        isRequired: false,
        isEditable: true,
        isEdited: true,
      ));
    });
  }

  void _removeRow(int index) {
    setState(() {
      _fields.removeAt(index);
    });
  }

  void _saveForm(BuildContext context) {
    // Validate
    for (int i = 0; i < _fields.length; i++) {
      if (_fields[i].label.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Field #${i + 1} label cannot be empty.'),
            backgroundColor: AppColors.primary,
          ),
        );
        return;
      }
    }

    final newFields = _fields.where((f) => f.id == null).toList();
    final modifiedFields = _fields.where((f) => f.id != null && f.isEdited).toList();

    if (newFields.isEmpty && modifiedFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No changes to save.'),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    _isSavingNew = newFields.isNotEmpty;
    _isUpdatingExisting = modifiedFields.isNotEmpty;

    if (_isSavingNew) {
      final payload = newFields.map((f) {
        final data = <String, dynamic>{
          'fieldLabel': f.label,
          'fieldType': f.type.toUpperCase(),
          'isRequired': f.isRequired,
          'displayOrder': f.displayOrder,
        };

        if (f.type.toUpperCase() == 'DROPDOWN' ||
            f.type.toUpperCase() == 'MULTI_SELECT' ||
            f.type.toUpperCase() == 'RADIO') {
          data['options'] = f.options;
        }

        if (f.type.toUpperCase() == 'ATTACHMENT') {
          data['attachmentType'] = 'DOCUMENT';
          if (f.minLength != null) data['minLength'] = f.minLength;
          if (f.maxLength != null) data['maxLength'] = f.maxLength;
        }

        return data;
      }).toList();

      context.read<SettingsBloc>().add(SaveCustomFields(payload));
    }

    if (_isUpdatingExisting) {
      final payload = modifiedFields.map((f) {
        final data = <String, dynamic>{
          'id': f.id,
          'fieldLabel': f.label,
          'fieldType': f.type.toUpperCase(),
          'isRequired': f.isRequired,
          'displayOrder': f.displayOrder,
        };

        if (f.type.toUpperCase() == 'DROPDOWN' ||
            f.type.toUpperCase() == 'MULTI_SELECT' ||
            f.type.toUpperCase() == 'RADIO') {
          data['options'] = f.options;
        }

        if (f.type.toUpperCase() == 'ATTACHMENT') {
          data['attachmentType'] = 'DOCUMENT';
          if (f.minLength != null) data['minLength'] = f.minLength;
          if (f.maxLength != null) data['maxLength'] = f.maxLength;
        }

        return data;
      }).toList();

      context.read<SettingsBloc>().add(UpdateCustomFields(payload));
    }
  }

  void _checkNavigationPop() {
    if (!_isSavingNew && !_isUpdatingExisting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom field changes saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listener: (context, state) {
        if (state is CustomFieldsLoaded && !_hasLoadedData) {
          _fieldTypes = List.from(state.types);
          final defaultTypes = ['TEXT', 'EMAIL', 'PHONE', 'NUMBER', 'DROPDOWN', 'MULTI_SELECT', 'RADIO', 'DATE', 'DATE_TIME', 'ATTACHMENT', 'TEXTAREA'];
          for (var dt in defaultTypes) {
            if (!_fieldTypes.contains(dt)) {
              _fieldTypes.add(dt);
            }
          }
          _fields = state.fields.map((f) {
            final rawType = f.type.isNotEmpty ? f.type : f.fieldType;
            return CustomFieldConfig(
              id: f.id,
              label: f.label.isNotEmpty ? f.label : f.fieldLabel,
              type: rawType.toUpperCase(),
              displayOrder: f.displayOrder,
              isRequired: f.isRequired,
              minLength: f.minLength,
              maxLength: f.maxLength,
              options: f.options,
              isEditable: false,
              isEdited: false,
            );
          }).toList();

          if (_fields.isEmpty) {
            _fields.add(CustomFieldConfig(
              label: 'Customer Name',
              type: _fieldTypes.contains('TEXT') ? 'TEXT' : (_fieldTypes.isNotEmpty ? _fieldTypes.first : 'TEXT'),
              displayOrder: 1,
              isRequired: true,
              isEditable: false,
              isEdited: false,
            ));
          }
          _hasLoadedData = true;
          _isLocalLoading = false;
        } else if (state is CustomFieldsSaved) {
          _isSavingNew = false;
          _checkNavigationPop();
        } else if (state is CustomFieldsUpdated) {
          _isUpdatingExisting = false;
          _checkNavigationPop();
        } else if (state is SettingsError) {
          _errorMessage = state.message;
          _isLocalLoading = false;
          _isSavingNew = false;
          _isUpdatingExisting = false;
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
              'Lead Custom Form',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
                tooltip: 'Refresh Form Layout',
                onPressed: () => context.read<SettingsBloc>().add(FetchCustomFields()),
              ),
              if (!showLoader && _hasLoadedData)
                IconButton(
                  icon: const Icon(Icons.check, color: AppColors.primary, size: 28),
                  onPressed: () => _saveForm(context),
                ),
            ],
          ),
          body: showLoader
              ? const Center(child: SpinningLogo(size: 60))
              : SafeArea(
                  child: Column(
                    children: [
                      if (state is SettingsLoading && _hasLoadedData)
                        const LinearProgressIndicator(color: AppColors.primary),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        color: AppColors.secondary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Primary Lead Form',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Bulk manage your dynamic form fields below',
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
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: _fields.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _fields.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16.0),
                                child: OutlinedButton.icon(
                                  onPressed: _isLocalLoading ? null : _addNewRow,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add New Row'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              );
                            }

                            final config = _fields[index];
                            return _buildFieldConfigCard(config, index);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildFieldConfigCard(CustomFieldConfig config, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        children: [
          // Header of field card (index, edit button, and delete)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'FIELD #${index + 1}${config.id == null ? ' (NEW)' : ''}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: config.id == null ? AppColors.primary : Colors.grey.shade600, letterSpacing: 0.5),
                ),
                if (config.id == null)
                  GestureDetector(
                    onTap: _isLocalLoading ? null : () => _removeRow(index),
                    child: const Icon(Icons.delete_outline, color: AppColors.primary, size: 18),
                  )
                else if (!config.isEditable)
                  GestureDetector(
                    onTap: _isLocalLoading ? null : () {
                      setState(() {
                        config.isEditable = true;
                      });
                    },
                    child: const Row(
                      children: [
                        Icon(Icons.edit_outlined, color: AppColors.primary, size: 14),
                        SizedBox(width: 4),
                        Text('Edit', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  const Row(
                    children: [
                      Icon(Icons.edit, color: Colors.grey, size: 14),
                      SizedBox(width: 4),
                      Text('Editing', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Field Label Input
                TextFormField(
                  initialValue: config.label,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  enabled: config.isEditable && !_isLocalLoading,
                  decoration: const InputDecoration(
                    labelText: 'Field Label *',
                    labelStyle: TextStyle(fontSize: 13, color: AppColors.textLabel),
                    hintText: 'e.g. Expected Close Date',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (val) {
                    config.label = val;
                    config.isEdited = true;
                  },
                ),
                const SizedBox(height: 12),
                // Type & Order Row
                Row(
                  children: [
                    // Type Dropdown
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        value: _fieldTypes.contains(config.type) ? config.type : (_fieldTypes.isNotEmpty ? _fieldTypes.first : 'TEXT'),
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          labelStyle: TextStyle(fontSize: 13, color: AppColors.textLabel),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: _fieldTypes
                            .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 14))))
                            .toList(),
                        onChanged: (config.isEditable && !_isLocalLoading) ? (val) {
                          if (val != null) {
                            setState(() {
                              config.type = val;
                              config.isEdited = true;
                            });
                          }
                        } : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Order
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        initialValue: config.displayOrder.toString(),
                        enabled: config.isEditable && !_isLocalLoading,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Order',
                          labelStyle: TextStyle(fontSize: 13, color: AppColors.textLabel),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (val) {
                          config.displayOrder = int.tryParse(val) ?? (index + 1);
                          config.isEdited = true;
                        },
                      ),
                    ),
                  ],
                ),
                // Constraints & Options
                if (config.type == 'TEXT' || config.type == 'TEXTAREA' || config.type == 'ATTACHMENT') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: config.minLength?.toString() ?? '',
                          enabled: config.isEditable && !_isLocalLoading,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: config.type == 'ATTACHMENT' ? 'Min Files' : 'Min Len',
                            labelStyle: const TextStyle(fontSize: 13, color: AppColors.textLabel),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (val) {
                            config.minLength = int.tryParse(val);
                            config.isEdited = true;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: config.maxLength?.toString() ?? '',
                          enabled: config.isEditable && !_isLocalLoading,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: config.type == 'ATTACHMENT' ? 'Max Files' : 'Max Len',
                            labelStyle: const TextStyle(fontSize: 13, color: AppColors.textLabel),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (val) {
                            config.maxLength = int.tryParse(val);
                            config.isEdited = true;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                if (config.type == 'DROPDOWN' || config.type == 'MULTI_SELECT' || config.type == 'RADIO') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: config.options.join(', '),
                    enabled: config.isEditable && !_isLocalLoading,
                    decoration: const InputDecoration(
                      labelText: 'Options (comma separated)',
                      labelStyle: TextStyle(fontSize: 13, color: AppColors.textLabel),
                      hintText: 'Hot, Warm, Cold',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) {
                      config.options = val.split(',').map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
                      config.isEdited = true;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                // Required Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Required Field',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textLabel),
                    ),
                    Switch(
                      value: config.isRequired,
                      activeColor: AppColors.primary,
                      onChanged: (config.isEditable && !_isLocalLoading) ? (val) {
                        setState(() {
                          config.isRequired = val;
                          config.isEdited = true;
                        });
                      } : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CustomFieldConfig {
  String? id;
  String label;
  String type;
  int displayOrder;
  bool isRequired;
  int? minLength;
  int? maxLength;
  List<String> options;
  bool isEditable;
  bool isEdited;

  CustomFieldConfig({
    this.id,
    required this.label,
    required this.type,
    required this.displayOrder,
    required this.isRequired,
    this.minLength,
    this.maxLength,
    List<String>? options,
    this.isEditable = false,
    this.isEdited = false,
  }) : options = options ?? [];
}
