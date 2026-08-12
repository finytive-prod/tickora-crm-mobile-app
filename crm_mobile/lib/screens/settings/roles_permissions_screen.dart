import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/spinning_logo.dart';

class RolesPermissionsScreen extends StatefulWidget {
  const RolesPermissionsScreen({super.key});

  @override
  State<RolesPermissionsScreen> createState() => _RolesPermissionsScreenState();
}

class _RolesPermissionsScreenState extends State<RolesPermissionsScreen> {
  bool _isLoading = false;
  String _selectedRole = 'Super Admin';
  final _roleNameController = TextEditingController(text: 'Super Admin');
  final _descriptionController = TextEditingController(text: 'Organization creator and absolute access');

  // List of modules matching the web screenshot
  final List<String> _modules = [
    'Customers',
    'Pipelines',
    'Followups',
    'Management',
    'Leads',
    'Users',
    'Reports',
    'Permissions',
  ];

  // Permissions state map: {Role: {Module: {Create: bool, Read: bool, Update: bool, Delete: bool}}}
  late Map<String, Map<String, Map<String, bool>>> _permissionsData;

  @override
  void initState() {
    super.initState();
    _initializePermissions();
  }

  @override
  void dispose() {
    _roleNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _initializePermissions() {
    _permissionsData = {
      'Super Admin': {
        for (var module in _modules)
          module: {'create': true, 'read': true, 'update': true, 'delete': true}
      },
      'Admin': {
        for (var module in _modules)
          module: {
            'create': true,
            'read': true,
            'update': true,
            'delete': module != 'Permissions'
          }
      },
      'Manager': {
        for (var module in _modules)
          module: {
            'create': module != 'Permissions' && module != 'Users',
            'read': true,
            'update': module != 'Permissions' && module != 'Users',
            'delete': false
          }
      },
      'Agent': {
        for (var module in _modules)
          module: {
            'create': module == 'Leads' || module == 'Followups',
            'read': module != 'Permissions' && module != 'Management',
            'update': module == 'Leads' || module == 'Followups',
            'delete': false
          }
      },
    };
  }

  void _onRoleChanged(String? role) {
    if (role == null) return;
    setState(() {
      _selectedRole = role;
      _roleNameController.text = role;

      // Update role description
      if (role == 'Super Admin') {
        _descriptionController.text = 'Organization creator and absolute access';
      } else if (role == 'Admin') {
        _descriptionController.text = 'Administrator access with configuration permissions';
      } else if (role == 'Manager') {
        _descriptionController.text = 'Department or team manager permissions';
      } else if (role == 'Agent') {
        _descriptionController.text = 'Standard sales agent access for lead tracking';
      }
    });
  }

  bool _isAllSelected(String module) {
    final perms = _permissionsData[_selectedRole]![module]!;
    return perms['create']! && perms['read']! && perms['update']! && perms['delete']!;
  }

  void _toggleSelectAll(String module, bool value) {
    setState(() {
      _permissionsData[_selectedRole]![module]!['create'] = value;
      _permissionsData[_selectedRole]![module]!['read'] = value;
      _permissionsData[_selectedRole]![module]!['update'] = value;
      _permissionsData[_selectedRole]![module]!['delete'] = value;
    });
  }

  void _togglePermission(String module, String type, bool value) {
    setState(() {
      _permissionsData[_selectedRole]![module]![type] = value;
    });
  }

  Future<void> _savePermissions() async {
    setState(() {
      _isLoading = true;
    });

    // Mock API delay
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permissions for "$_selectedRole" saved successfully!'),
          backgroundColor: Colors.green,
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
          'Roles & Permissions',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.check, color: AppColors.primary, size: 28),
              onPressed: _savePermissions,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: SpinningLogo(size: 60))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subtitle Header
                    const Text(
                      'Control module access for each role',
                      style: TextStyle(color: AppColors.textHint, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Role Selection & Info card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.borderEnabled),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dropdown selector
                          DropdownButtonFormField<String>(
                            value: _selectedRole,
                            decoration: const InputDecoration(
                              labelText: 'Select Role',
                              labelStyle: TextStyle(color: AppColors.textLabel, fontWeight: FontWeight.bold),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: ['Super Admin', 'Admin', 'Manager', 'Agent']
                                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                                .toList(),
                            onChanged: _onRoleChanged,
                          ),
                          const SizedBox(height: 16),
                          // Role Name Input
                          TextFormField(
                            controller: _roleNameController,
                            decoration: const InputDecoration(
                              labelText: 'Role Name',
                              labelStyle: TextStyle(color: AppColors.textLabel),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onChanged: (val) {
                              // Allow local name editing if desired
                            },
                          ),
                          const SizedBox(height: 16),
                          // Description Input
                          TextFormField(
                            controller: _descriptionController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              labelStyle: TextStyle(color: AppColors.textLabel),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Permissions list title
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'View Roles & Permissions',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Permissions List Cards
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _modules.length,
                      itemBuilder: (context, index) {
                        final module = _modules[index];
                        final isAll = _isAllSelected(module);
                        final perms = _permissionsData[_selectedRole]![module]!;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.borderEnabled),
                          ),
                          child: ExpansionTile(
                            shape: const Border(), // Remove default borders
                            backgroundColor: Colors.transparent,
                            title: Text(
                              module,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                            ),
                            subtitle: Text(
                              isAll 
                                  ? 'All Permissions Granted' 
                                  : 'Custom Permissions configured',
                              style: TextStyle(fontSize: 12, color: isAll ? Colors.green : AppColors.textHint),
                            ),
                            children: [
                              const Divider(height: 1, color: AppColors.borderEnabled),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    // Select All Checkbox row
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Select all',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                                        ),
                                        Checkbox(
                                          value: isAll,
                                          activeColor: AppColors.primary,
                                          onChanged: (val) => _toggleSelectAll(module, val ?? false),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 16, color: AppColors.borderEnabled),
                                    // Individual permissions checkboxes
                                    _buildPermissionRow(module, 'Create', 'create', perms['create']!),
                                    _buildPermissionRow(module, 'Read', 'read', perms['read']!),
                                    _buildPermissionRow(module, 'Update', 'update', perms['update']!),
                                    _buildPermissionRow(module, 'Delete', 'delete', perms['delete']!),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPermissionRow(String module, String title, String type, bool value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        ),
        Checkbox(
          value: value,
          activeColor: AppColors.primary,
          onChanged: (val) => _togglePermission(module, type, val ?? false),
        ),
      ],
    );
  }
}
