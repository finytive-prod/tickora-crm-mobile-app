import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/blocs/settings_bloc.dart';
import 'package:crm_mobile/blocs/settings_event.dart';
import 'package:crm_mobile/blocs/settings_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/widgets/custom_text_field.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';
import 'package:crm_mobile/core/utils/form_validator_utils.dart';

class LeadSourcesScreen extends StatelessWidget {
  const LeadSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<SettingsBloc>()..add(FetchLeadSources()),
      child: const LeadSourcesView(),
    );
  }
}

class LeadSourcesView extends StatefulWidget {
  const LeadSourcesView({super.key});

  @override
  State<LeadSourcesView> createState() => _LeadSourcesViewState();
}

class _LeadSourcesViewState extends State<LeadSourcesView> {
  bool _isLocalLoading = false;
  String? _errorMessage;
  List<LeadSource> _sources = [];
  bool _hasLoadedData = false;

  // Form states for creating source
  final _formKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = 'SOCIAL_MEDIA';
  bool _isEnabled = true;

  // Dynamic categories list from API
  List<String> _categories = [];

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _createSource(BuildContext context) {
    if (!validateAndScrollToError(_formKey)) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }

    final sourceData = {
      'name': _nameController.text.trim(),
      'category': _selectedCategory,
      'description': _descController.text.trim(),
      'active': _isEnabled,
    };

    context.read<SettingsBloc>().add(CreateLeadSource(sourceData));
  }

  void _deleteSource(BuildContext context, LeadSource source) {
    context.read<SettingsBloc>().add(DeleteLeadSource(source.id));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listener: (context, state) {
        if (state is LeadSourcesLoaded) {
          _sources = List.from(state.sources);
          _categories = List.from(state.categories);
          if (_categories.isNotEmpty && !_categories.contains(_selectedCategory)) {
            _selectedCategory = _categories.first;
          }
          _hasLoadedData = true;
          _isLocalLoading = false;
        } else if (state is LeadSourceCreated) {
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lead source created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Reset form
          _nameController.clear();
          _descController.clear();
          if (_categories.isNotEmpty) {
            _selectedCategory = _categories.first;
          }
          _isEnabled = true;
          context.read<SettingsBloc>().add(FetchLeadSources());
        } else if (state is LeadSourceDeleted) {
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lead source deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          context.read<SettingsBloc>().add(FetchLeadSources());
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
              icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Lead Sources',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
                tooltip: 'Refresh Sources',
                onPressed: () => context.read<SettingsBloc>().add(FetchLeadSources()),
              ),
            ],
          ),
          body: showLoader
              ? const Center(child: SpinningLogo(size: 60))
              : SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (state is SettingsLoading && _hasLoadedData)
                          const LinearProgressIndicator(color: AppColors.primary),
                        // Subtitle Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Active Lead Channels',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Configure acquisition channels like Google Ads, Website, Facebook, etc.',
                                style: TextStyle(color: AppColors.textHint, fontSize: 12),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Empty State if no sources
                        if (_sources.isEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderEnabled),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.people_alt_outlined, size: 36, color: AppColors.textHint),
                                SizedBox(height: 8),
                                Text(
                                  'No Lead Sources Found',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Create a lead source below to start tracking your channels.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppColors.textHint),
                                ),
                              ],
                            ),
                          ),

                        // List of current sources
                        if (_sources.isNotEmpty)
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            itemCount: _sources.length,
                            itemBuilder: (context, index) {
                              final source = _sources[index];
                              final cleanCategory = source.category.trim();
                              final hasCategory = cleanCategory.isNotEmpty && cleanCategory != '-';
                              final cleanDesc = source.description.trim();
                              final hasDescription = cleanDesc.isNotEmpty && cleanDesc != '-';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8.0),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.borderEnabled),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                source.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              if (hasCategory)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.secondary,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: AppColors.borderEnabled),
                                                  ),
                                                  child: Text(
                                                    cleanCategory,
                                                    style: const TextStyle(
                                                      color: AppColors.textSecondary,
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Active status badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: source.active ? const Color(0xFFECFDF5) : AppColors.secondary,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: source.active ? const Color(0xFFA7F3D0) : AppColors.borderEnabled,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 3,
                                                backgroundColor: source.active ? const Color(0xFF059669) : AppColors.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                source.active ? 'Active' : 'Inactive',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: source.active ? const Color(0xFF047857) : AppColors.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: _isLocalLoading ? null : () => _deleteSource(context, source),
                                          borderRadius: BorderRadius.circular(4),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.delete_outline, color: AppColors.primary, size: 18),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (hasDescription) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        cleanDesc,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 8),

                        // Create Lead Source Form Section (White card)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
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
                                    Icon(Icons.add_circle_outline, color: AppColors.primary, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Create Lead Source',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Source Name
                                CustomTextField(
                                  label: 'Source Name',
                                  isRequired: true,
                                  controller: _nameController,
                                  enabled: !_isLocalLoading,
                                  hintText: 'e.g. Instagram Influencers',
                                  autovalidateMode: _autovalidateMode,
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Source Name is required';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),

                                // Category Dropdown
                                CustomDropdownField<String>(
                                  label: 'Source Category / Type',
                                  isRequired: true,
                                  enabled: !_isLocalLoading,
                                  autovalidateMode: _autovalidateMode,
                                  value: _categories.contains(_selectedCategory)
                                      ? _selectedCategory
                                      : (_categories.isNotEmpty ? _categories.first : null),
                                  items: _categories
                                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14))))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedCategory = val;
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),

                                // Description
                                CustomTextField(
                                  label: 'Description',
                                  controller: _descController,
                                  enabled: !_isLocalLoading,
                                  maxLines: 2,
                                  hintText: 'Notes about this source tracking channel...',
                                  autovalidateMode: _autovalidateMode,
                                ),
                                const SizedBox(height: 12),

                                // Enable checkbox
                                InkWell(
                                  onTap: _isLocalLoading
                                      ? null
                                      : () {
                                          setState(() {
                                            _isEnabled = !_isEnabled;
                                          });
                                        },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: Checkbox(
                                            value: _isEnabled,
                                            activeColor: AppColors.primary,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                            onChanged: _isLocalLoading
                                                ? null
                                                : (val) {
                                                    setState(() {
                                                      _isEnabled = val ?? true;
                                                    });
                                                  },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Enable source for selection',
                                          style: TextStyle(fontSize: 13, color: AppColors.textLabel, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Create Source Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _isLocalLoading ? null : () => _createSource(context),
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Create Source'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

