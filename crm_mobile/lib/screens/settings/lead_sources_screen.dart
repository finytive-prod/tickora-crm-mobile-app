import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/blocs/settings_bloc.dart';
import 'package:crm_mobile/blocs/settings_event.dart';
import 'package:crm_mobile/blocs/settings_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
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
    if (!validateAndScrollToError(_formKey)) return;

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
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Lead Sources',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            centerTitle: true,
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
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Active Lead Channels',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Configure acquisition channels like Google Ads, Website, Facebook, etc.',
                                style: TextStyle(color: AppColors.textHint, fontSize: 12),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // List of current sources
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _sources.length,
                          itemBuilder: (context, index) {
                            final source = _sources[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12.0),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.borderEnabled),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name & Actions Row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          source.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _isLocalLoading ? null : () => _deleteSource(context, source),
                                        child: const Icon(Icons.delete_outline, color: AppColors.primary, size: 20),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // Category badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.grey.shade300, width: 0.5),
                                    ),
                                    child: Text(
                                      source.category,
                                      style: TextStyle(color: Colors.grey.shade700, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Description
                                  Text(
                                    source.description.isNotEmpty ? source.description : 'No description provided.',
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1, color: AppColors.borderEnabled),
                                  const SizedBox(height: 10),
                                  // Active Status Badge / Toggle
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Active Status',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textLabel),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: source.active ? Colors.green.shade50 : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: source.active ? Colors.green.shade200 : Colors.red.shade200),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 4,
                                              backgroundColor: source.active ? Colors.green : Colors.red,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              source.active ? 'Active' : 'Inactive',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: source.active ? Colors.green.shade700 : Colors.red.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 8),

                        // Create Lead Source Form Section (White card)
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Create Lead Source',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Source Name
                                TextFormField(
                                  controller: _nameController,
                                  enabled: !_isLocalLoading,
                                  decoration: const InputDecoration(
                                    labelText: 'Source Name',
                                    hintText: 'e.g. Instagram Influencers',
                                    labelStyle: TextStyle(color: AppColors.textLabel),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Source Name is required';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Category Dropdown
                                DropdownButtonFormField<String>(
                                  value: _categories.contains(_selectedCategory)
                                      ? _selectedCategory
                                      : (_categories.isNotEmpty ? _categories.first : null),
                                  decoration: const InputDecoration(
                                    labelText: 'Source Category / Type',
                                    labelStyle: TextStyle(color: AppColors.textLabel),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  items: _categories
                                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14))))
                                      .toList(),
                                  onChanged: _isLocalLoading
                                      ? null
                                      : (val) {
                                          if (val != null) {
                                            setState(() {
                                              _selectedCategory = val;
                                            });
                                          }
                                        },
                                ),
                                const SizedBox(height: 16),

                                // Description
                                TextFormField(
                                  controller: _descController,
                                  enabled: !_isLocalLoading,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Description',
                                    hintText: 'Notes about this source tracking channel...',
                                    labelStyle: TextStyle(color: AppColors.textLabel),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Enable checkbox
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _isEnabled,
                                      activeColor: AppColors.primary,
                                      onChanged: _isLocalLoading
                                          ? null
                                          : (val) {
                                              setState(() {
                                                _isEnabled = val ?? true;
                                              });
                                            },
                                    ),
                                    const Text(
                                      'Enable source for selection',
                                      style: TextStyle(fontSize: 13, color: AppColors.textLabel, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),

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
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
