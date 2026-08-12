import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../features/leads/domain/usecases/get_lead_sources_usecase.dart';
import '../../injection/injection.dart';
import '../../widgets/spinning_logo.dart';

class LeadSourcesScreen extends StatefulWidget {
  const LeadSourcesScreen({super.key});

  @override
  State<LeadSourcesScreen> createState() => _LeadSourcesScreenState();
}

class _LeadSourcesScreenState extends State<LeadSourcesScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<LeadSourceConfig> _sources = [];

  // Form states for creating source
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = 'SOCIAL_MEDIA';
  bool _isEnabled = true;

  // Categories list matching web screenshot
  final List<String> _categories = [
    'SOCIAL_MEDIA',
    'SEARCH_ENGINE',
    'REFERRAL',
    'DIGITAL',
    'OTHER',
  ];

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final getSources = sl<GetLeadSourcesUseCase>();
    final result = await getSources();

    result.fold(
      (failure) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load sources. Loaded local simulation.';
          _sources = _getMockSources();
        });
      },
      (sources) {
        setState(() {
          _isLoading = false;
          _sources = sources.map((s) => LeadSourceConfig(
            id: s.id,
            name: s.name,
            category: s.category,
            description: s.description,
            isActive: true, // Default to true for loaded sources
          )).toList();

          if (_sources.isEmpty) {
            _sources = _getMockSources();
          }
        });
      },
    );
  }

  List<LeadSourceConfig> _getMockSources() {
    return [
      LeadSourceConfig(id: '1', name: 'Facebook', category: 'SOCIAL_MEDIA', description: 'Meta Ads and lead gen forms', isActive: true),
      LeadSourceConfig(id: '2', name: 'Google', category: 'SEARCH_ENGINE', description: 'Google PPC campaign inbound leads', isActive: true),
      LeadSourceConfig(id: '3', name: 'Referral', category: 'REFERRAL', description: 'Introductions from existing clients', isActive: true),
      LeadSourceConfig(id: '4', name: 'Website', category: 'DIGITAL', description: 'Inbound organic forms filled on site', isActive: true),
    ];
  }

  Future<void> _createSource() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final newSourceName = _nameController.text.trim();
    final description = _descController.text.trim();

    // Mock API delay
    await Future.delayed(const Duration(milliseconds: 800));

    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newSource = LeadSourceConfig(
      id: newId,
      name: newSourceName,
      category: _selectedCategory,
      description: description.isNotEmpty ? description : 'No description provided.',
      isActive: _isEnabled,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _sources.add(newSource);
        
        // Reset form
        _nameController.clear();
        _descController.clear();
        _selectedCategory = 'SOCIAL_MEDIA';
        _isEnabled = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Source "$newSourceName" created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteSource(LeadSourceConfig source) async {
    setState(() {
      _isLoading = true;
    });

    // Mock API delay
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      setState(() {
        _isLoading = false;
        _sources.removeWhere((s) => s.id == source.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Source "${source.name}" deleted successfully!'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: _isLoading
          ? const Center(child: SpinningLogo(size: 60))
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                    onTap: () => _deleteSource(source),
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
                                source.description,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: AppColors.borderEnabled),
                              const SizedBox(height: 10),
                              // Active Status Toggle
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Active / Selectable',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textLabel),
                                  ),
                                  Switch(
                                    value: source.isActive,
                                    activeColor: AppColors.primary,
                                    onChanged: (val) {
                                      setState(() {
                                        source.isActive = val;
                                      });
                                    },
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
                              value: _selectedCategory,
                              decoration: const InputDecoration(
                                labelText: 'Source Category / Type',
                                labelStyle: TextStyle(color: AppColors.textLabel),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
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
                            const SizedBox(height: 16),

                            // Description
                            TextFormField(
                              controller: _descController,
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
                                  onChanged: (val) {
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
                                onPressed: _createSource,
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
  }
}

class LeadSourceConfig {
  final String id;
  final String name;
  final String category;
  final String description;
  bool isActive;

  LeadSourceConfig({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.isActive,
  });
}
