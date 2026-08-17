import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/permission_module.dart';
import 'package:crm_mobile/models/role_entity.dart';
import 'package:crm_mobile/blocs/settings_bloc.dart';
import 'package:crm_mobile/blocs/settings_event.dart';
import 'package:crm_mobile/blocs/settings_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';

class RolesPermissionsScreen extends StatelessWidget {
  const RolesPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<SettingsBloc>()
        ..add(FetchPermissionModules())
        ..add(FetchRolesDropdown()),
      child: const RolesPermissionsView(),
    );
  }
}

class RolesPermissionsView extends StatefulWidget {
  const RolesPermissionsView({super.key});

  @override
  State<RolesPermissionsView> createState() => _RolesPermissionsViewState();
}

class _RolesPermissionsViewState extends State<RolesPermissionsView> {
  bool _isLocalLoading = false;
  String? _errorMessage;

  List<PermissionModule> _modules = [];
  List<RoleDropdownItem> _rolesDropdown = [];
  RoleDropdownItem? _selectedRole;

  final _roleNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Permissions state map: {ModuleCode: {create: bool, read: bool, update: bool, delete: bool}}
  Map<String, Map<String, bool>> _permissionsMap = {};
  bool _hasLoadedData = false;

  @override
  void dispose() {
    _roleNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool _isModuleMatch(String rolePermModule, String moduleCode) {
    final a = rolePermModule.toUpperCase();
    final b = moduleCode.toUpperCase();
    return a == b || a == '${b}S' || '${a}S' == b || a == b.replaceAll(RegExp(r'S$'), '');
  }

  void _populateRoleDetails(RoleDetail roleDetail) {
    _roleNameController.text = roleDetail.roleName;
    _descriptionController.text = roleDetail.description;

    _permissionsMap = {};
    for (var m in _modules) {
      RolePermission? matchedPerm;
      for (var p in roleDetail.permissions) {
        if (_isModuleMatch(p.module, m.module) || _isModuleMatch(p.module, m.displayName)) {
          matchedPerm = p;
          break;
        }
      }

      _permissionsMap[m.module] = {
        'create': matchedPerm?.create ?? false,
        'read': matchedPerm?.read ?? false,
        'update': matchedPerm?.update ?? false,
        'delete': matchedPerm?.delete ?? false,
      };
    }
  }

  bool _isAllSelected(String moduleCode) {
    final perms = _permissionsMap[moduleCode];
    if (perms == null) return false;
    return (perms['create'] ?? false) &&
        (perms['read'] ?? false) &&
        (perms['update'] ?? false) &&
        (perms['delete'] ?? false);
  }

  void _toggleSelectAll(String moduleCode, bool value) {
    setState(() {
      _permissionsMap[moduleCode] = {
        'create': value,
        'read': value,
        'update': value,
        'delete': value,
      };
    });
  }

  void _togglePermission(String moduleCode, String type, bool value) {
    setState(() {
      if (!_permissionsMap.containsKey(moduleCode)) {
        _permissionsMap[moduleCode] = {'create': false, 'read': false, 'update': false, 'delete': false};
      }
      _permissionsMap[moduleCode]![type] = value;
    });
  }

  void _onRoleSelected(RoleDropdownItem? role) {
    if (role == null) return;
    setState(() {
      _selectedRole = role;
    });
    context.read<SettingsBloc>().add(FetchRoleDetails(role.id));
  }

  void _saveRolePermissions(BuildContext context) {
    if (_selectedRole == null) return;

    final permissionsList = _modules.map((m) {
      final perms = _permissionsMap[m.module] ?? {'create': false, 'read': false, 'update': false, 'delete': false};
      return {
        'module': m.module,
        'create': perms['create'] ?? false,
        'read': perms['read'] ?? false,
        'update': perms['update'] ?? false,
        'delete': perms['delete'] ?? false,
      };
    }).toList();

    final roleData = {
      'roleName': _roleNameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'permissions': permissionsList,
    };

    context.read<SettingsBloc>().add(UpdateRole(_selectedRole!.id, roleData));
  }

  void _openCreateRolePanel(BuildContext context) {
    final settingsBloc = context.read<SettingsBloc>();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Create Role',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: CreateRoleRightPanel(
              modules: _modules,
              settingsBloc: settingsBloc,
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listener: (context, state) {
        if (state is PermissionModulesLoaded) {
          _modules = state.modules;
          _hasLoadedData = true;
          _isLocalLoading = false;
        } else if (state is RolesDropdownLoaded) {
          _rolesDropdown = state.roles;
          _isLocalLoading = false;
          if (_rolesDropdown.isNotEmpty) {
            if (_selectedRole == null || !_rolesDropdown.any((r) => r.id == _selectedRole!.id)) {
              _selectedRole = _rolesDropdown.first;
            }
            context.read<SettingsBloc>().add(FetchRoleDetails(_selectedRole!.id));
          }
        } else if (state is RoleDetailsLoaded) {
          _isLocalLoading = false;
          _populateRoleDetails(state.roleDetail);
        } else if (state is RoleCreated) {
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Role created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          context.read<SettingsBloc>().add(FetchRolesDropdown());
        } else if (state is RoleUpdated) {
          _isLocalLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Role permissions updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          context.read<SettingsBloc>().add(FetchRolesDropdown());
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
              'Roles & Permissions',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 26),
                tooltip: 'Create New Role',
                onPressed: _isLocalLoading ? null : () => _openCreateRolePanel(context),
              ),
              IconButton(
                icon: const Icon(Icons.save_outlined, color: AppColors.primary, size: 26),
                tooltip: 'Save Role Changes',
                onPressed: _isLocalLoading ? null : () => _saveRolePermissions(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: showLoader
              ? const Center(child: SpinningLogo(size: 60))
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (state is SettingsLoading && _hasLoadedData)
                          const LinearProgressIndicator(color: AppColors.primary),
                        // Subtitle Header
                        const Text(
                          'Control module access for each role',
                          style: TextStyle(color: AppColors.textHint, fontSize: 13),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ],
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
                              // Backend Roles Dropdown selector
                              DropdownButtonFormField<RoleDropdownItem>(
                                value: _selectedRole,
                                decoration: const InputDecoration(
                                  labelText: 'Select Role',
                                  labelStyle: TextStyle(color: AppColors.textLabel, fontWeight: FontWeight.bold),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: _rolesDropdown
                                    .map((r) => DropdownMenuItem<RoleDropdownItem>(
                                          value: r,
                                          child: Text(r.roleName),
                                        ))
                                    .toList(),
                                onChanged: _isLocalLoading ? null : _onRoleSelected,
                              ),
                              const SizedBox(height: 16),
                              // Role Name Input
                              TextFormField(
                                controller: _roleNameController,
                                enabled: !_isLocalLoading,
                                decoration: const InputDecoration(
                                  labelText: 'Role Name',
                                  labelStyle: TextStyle(color: AppColors.textLabel),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Description Input
                              TextFormField(
                                controller: _descriptionController,
                                enabled: !_isLocalLoading,
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
                              'Module Permissions Config',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Dynamic Permissions List Cards
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _modules.length,
                          itemBuilder: (context, index) {
                            final module = _modules[index];
                            final moduleCode = module.module;
                            final displayName = module.displayName;
                            final isAll = _isAllSelected(moduleCode);
                            final perms = _permissionsMap[moduleCode] ??
                                {'create': false, 'read': false, 'update': false, 'delete': false};

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12.0),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.borderEnabled),
                              ),
                              child: ExpansionTile(
                                shape: const Border(),
                                backgroundColor: Colors.transparent,
                                title: Text(
                                  displayName,
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
                                              onChanged: _isLocalLoading ? null : (val) => _toggleSelectAll(moduleCode, val ?? false),
                                            ),
                                          ],
                                        ),
                                        const Divider(height: 16, color: AppColors.borderEnabled),
                                        // Individual permissions checkboxes
                                        _buildPermissionRow(moduleCode, 'Create', 'create', perms['create'] ?? false),
                                        _buildPermissionRow(moduleCode, 'Read', 'read', perms['read'] ?? false),
                                        _buildPermissionRow(moduleCode, 'Update', 'update', perms['update'] ?? false),
                                        _buildPermissionRow(moduleCode, 'Delete', 'delete', perms['delete'] ?? false),
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
      },
    );
  }

  Widget _buildPermissionRow(String moduleCode, String title, String type, bool value) {
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
          onChanged: _isLocalLoading ? null : (val) => _togglePermission(moduleCode, type, val ?? false),
        ),
      ],
    );
  }
}

// Side Screen Panel for Create Role (sliding from right)
class CreateRoleRightPanel extends StatefulWidget {
  final List<PermissionModule> modules;
  final SettingsBloc settingsBloc;

  const CreateRoleRightPanel({
    super.key,
    required this.modules,
    required this.settingsBloc,
  });

  @override
  State<CreateRoleRightPanel> createState() => _CreateRoleRightPanelState();
}

class _CreateRoleRightPanelState extends State<CreateRoleRightPanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  late Map<String, Map<String, bool>> _createPermissionsMap;

  @override
  void initState() {
    super.initState();
    _createPermissionsMap = {
      for (var m in widget.modules)
        m.module: {'create': true, 'read': true, 'update': true, 'delete': true}
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool _isAllSelected(String moduleCode) {
    final perms = _createPermissionsMap[moduleCode]!;
    return perms['create']! && perms['read']! && perms['update']! && perms['delete']!;
  }

  void _toggleSelectAll(String moduleCode, bool value) {
    setState(() {
      _createPermissionsMap[moduleCode] = {
        'create': value,
        'read': value,
        'update': value,
        'delete': value,
      };
    });
  }

  void _togglePermission(String moduleCode, String type, bool value) {
    setState(() {
      _createPermissionsMap[moduleCode]![type] = value;
    });
  }

  void _submitCreateRole() {
    if (!_formKey.currentState!.validate()) return;

    final permissionsList = widget.modules.map((m) {
      final perms = _createPermissionsMap[m.module] ?? {'create': true, 'read': true, 'update': true, 'delete': true};
      return {
        'module': m.module,
        'create': perms['create'] ?? true,
        'read': perms['read'] ?? true,
        'update': perms['update'] ?? true,
        'delete': perms['delete'] ?? true,
      };
    }).toList();

    final roleData = {
      'roleName': _nameController.text.trim(),
      'description': _descController.text.trim(),
      'permissions': permissionsList,
    };

    widget.settingsBloc.add(CreateRole(roleData));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: screenWidth * 0.88,
      height: double.infinity,
      color: AppColors.secondary,
      child: SafeArea(
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.add_circle, color: AppColors.primary, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Create Role',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderEnabled),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Role Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Role Name',
                          hintText: 'e.g. Tele Caller',
                          labelStyle: TextStyle(color: AppColors.textLabel),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Role Name is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _descController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Describe role responsibilities...',
                          labelStyle: TextStyle(color: AppColors.textLabel),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Description is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Module Permissions Config Title
                      const Text(
                        'Configure Module Permissions',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 12),

                      // List of module checkboxes
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.modules.length,
                        itemBuilder: (context, index) {
                          final module = widget.modules[index];
                          final moduleCode = module.module;
                          final displayName = module.displayName;
                          final isAll = _isAllSelected(moduleCode);
                          final perms = _createPermissionsMap[moduleCode]!;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderEnabled),
                            ),
                            child: ExpansionTile(
                              shape: const Border(),
                              title: Text(
                                displayName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                              ),
                              children: [
                                const Divider(height: 1, color: AppColors.borderEnabled),
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Select all', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                          Checkbox(
                                            value: isAll,
                                            activeColor: AppColors.primary,
                                            onChanged: (val) => _toggleSelectAll(moduleCode, val ?? false),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 12, color: AppColors.borderEnabled),
                                      _buildPanelPermRow(moduleCode, 'Create', 'create', perms['create']!),
                                      _buildPanelPermRow(moduleCode, 'Read', 'read', perms['read']!),
                                      _buildPanelPermRow(moduleCode, 'Update', 'update', perms['update']!),
                                      _buildPanelPermRow(moduleCode, 'Delete', 'delete', perms['delete']!),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submitCreateRole,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Save Role'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelPermRow(String moduleCode, String title, String type, bool value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
        Checkbox(
          value: value,
          activeColor: AppColors.primary,
          onChanged: (val) => _togglePermission(moduleCode, type, val ?? false),
        ),
      ],
    );
  }
}
