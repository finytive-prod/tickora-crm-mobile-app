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
import 'package:crm_mobile/core/utils/form_validator_utils.dart';

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
  bool _showingPermissionsMatrix = false;
  bool _isLocalLoading = false;
  String? _errorMessage;

  List<PermissionModule> _modules = [];
  List<RoleDropdownItem> _rolesDropdown = [];
  RoleDropdownItem? _selectedRole;

  final _roleNameController = TextEditingController();
  final _descriptionController = TextEditingController();

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

  void _openRolePanel(BuildContext context, {RoleDropdownItem? roleToEdit}) {
    final settingsBloc = context.read<SettingsBloc>();
    if (roleToEdit != null) {
      settingsBloc.add(FetchRoleDetails(roleToEdit.id));
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: roleToEdit != null ? 'Edit Role' : 'Create Role',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: RoleFormRightPanel(
              modules: _modules,
              settingsBloc: settingsBloc,
              roleToEdit: roleToEdit,
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
              content: Text('Role updated successfully!'),
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
              icon: Icon(_showingPermissionsMatrix ? Icons.arrow_back : Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () {
                if (_showingPermissionsMatrix) {
                  setState(() {
                    _showingPermissionsMatrix = false;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            title: Text(
              _showingPermissionsMatrix ? 'Permissions Matrix' : 'Roles & Permissions',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              if (_showingPermissionsMatrix) ...[
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showingPermissionsMatrix = false;
                    });
                  },
                  icon: const Icon(Icons.list_alt_rounded, size: 18, color: AppColors.primary),
                  label: const Text('View Roles', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.save_outlined, color: AppColors.primary, size: 26),
                  tooltip: 'Save Permissions',
                  onPressed: _isLocalLoading ? null : () => _saveRolePermissions(context),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.textPrimary),
                  tooltip: 'Refresh Roles',
                  onPressed: () => context.read<SettingsBloc>().add(FetchRolesDropdown()),
                ),
              ],
              const SizedBox(width: 8),
            ],
          ),
          body: showLoader
              ? const Center(child: SpinningLogo(size: 60))
              : SafeArea(
                  child: _showingPermissionsMatrix
                      ? _buildPermissionsMatrixView(state)
                      : _buildRolesListView(),
                ),
        );
      },
    );
  }

  Widget _buildRolesListView() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16.0),
      buildDefaultDragHandles: false,
      itemCount: _rolesDropdown.length,
      header: Column(
        key: const ValueKey('roles_header'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

          // Action Buttons: Create New Role & View Permissions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openRolePanel(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create new role'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showingPermissionsMatrix = true;
                    });
                  },
                  icon: const Icon(Icons.shield_outlined, size: 18, color: AppColors.primary),
                  label: const Text('View permissions'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Table Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border.all(color: AppColors.borderEnabled),
            ),
            child: const Row(
              children: [
                SizedBox(width: 28),
                Expanded(
                  child: Text(
                    'ROLE NAME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  'ACTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      onReorder: (oldIndex, newIndex) {
        // First 3 roles cannot be moved
        if (oldIndex < 3 || newIndex < 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The first 3 system roles cannot be moved.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        if (newIndex > oldIndex) {
          newIndex -= 1;
        }

        final item = _rolesDropdown.removeAt(oldIndex);
        _rolesDropdown.insert(newIndex, item);
        final newPriority = newIndex + 1;

        // Automatically call reorder API
        context.read<SettingsBloc>().add(ReorderRolePriority(item.id, newPriority));
      },
      itemBuilder: (context, index) {
        final role = _rolesDropdown[index];
        final isFixedRole = index < 3 || role.systemRole;
        final priority = role.priority > 0 ? role.priority : (index + 1);
        final description = _getRoleDescription(role, index);

        return Container(
          key: ValueKey(role.id),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.borderEnabled),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
            child: Row(
              children: [
                // Lock Icon for first 3 roles, Drag Handle for others
                if (isFixedRole)
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  )
                else
                  ReorderableDragStartListener(
                    index: index,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.transparent,
                      child: const Icon(
                        Icons.drag_indicator_rounded,
                        size: 22,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),

                // Role Name, Priority Badge & Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              role.roleName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Priority $priority',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // User / View permissions button
                    InkWell(
                      onTap: () {
                        _onRoleSelected(role);
                        setState(() {
                          _showingPermissionsMatrix = true;
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Edit role button -> Opens Role Form Panel in Edit Mode!
                    InkWell(
                      onTap: () {
                        _onRoleSelected(role);
                        _openRolePanel(context, roleToEdit: role);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getRoleDescription(RoleDropdownItem role, int index) {
    if (role.description.isNotEmpty) return role.description;
    final code = role.roleCode.toUpperCase();
    final name = role.roleName.toUpperCase();

    if (code.contains('SUPER') || name.contains('SUPER')) {
      return 'Organization creator and absolute access';
    } else if (code.contains('ADMIN') || name.contains('ADMIN')) {
      return 'Administrator with full access';
    } else if (code.contains('STAFF') || name.contains('STAFF')) {
      return 'General staff with limited access';
    }
    return 'Custom role permissions and module access';
  }

  Widget _buildPermissionsMatrixView(SettingsState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state is SettingsLoading && _hasLoadedData)
            const LinearProgressIndicator(color: AppColors.primary),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _showingPermissionsMatrix = false;
                  });
                },
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text('Back to Roles', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isLocalLoading ? null : () => _saveRolePermissions(context),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Role Selection Card
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

          // Permissions Matrix Title
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

          // Permissions List Cards
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
                    isAll ? 'All Permissions Granted' : 'Custom Permissions configured',
                    style: TextStyle(fontSize: 12, color: isAll ? Colors.green : AppColors.textHint),
                  ),
                  children: [
                    const Divider(height: 1, color: AppColors.borderEnabled),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
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

// Unified Side Screen Panel for Create & Edit Role
class RoleFormRightPanel extends StatefulWidget {
  final List<PermissionModule> modules;
  final SettingsBloc settingsBloc;
  final RoleDropdownItem? roleToEdit;

  const RoleFormRightPanel({
    super.key,
    required this.modules,
    required this.settingsBloc,
    this.roleToEdit,
  });

  @override
  State<RoleFormRightPanel> createState() => _RoleFormRightPanelState();
}

class _RoleFormRightPanelState extends State<RoleFormRightPanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _priorityController = TextEditingController();
  final _descController = TextEditingController();

  Map<String, Map<String, bool>> _createPermissionsMap = {};
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.roleToEdit != null;

    if (_isEditing && widget.roleToEdit != null) {
      _nameController.text = widget.roleToEdit!.roleName;
      _codeController.text = widget.roleToEdit!.roleCode;
      _priorityController.text = widget.roleToEdit!.priority > 0 ? widget.roleToEdit!.priority.toString() : '4';
      _descController.text = widget.roleToEdit!.description;
    } else {
      _priorityController.text = '5';
    }

    for (var m in widget.modules) {
      _createPermissionsMap[m.module] = {
        'create': true,
        'read': true,
        'update': true,
        'delete': true,
      };
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _priorityController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _populateFromRoleDetail(RoleDetail roleDetail) {
    if (!mounted) return;
    setState(() {
      _nameController.text = roleDetail.roleName;
      _codeController.text = roleDetail.roleCode;
      _priorityController.text = roleDetail.priority.toString();
      _descController.text = roleDetail.description;

      for (var m in widget.modules) {
        RolePermission? matchedPerm;
        for (var p in roleDetail.permissions) {
          if (p.module.toUpperCase() == m.module.toUpperCase() ||
              p.module.toUpperCase() == '${m.module.toUpperCase()}S' ||
              '${p.module.toUpperCase()}S' == m.module.toUpperCase() ||
              p.module.toUpperCase() == m.displayName.toUpperCase()) {
            matchedPerm = p;
            break;
          }
        }

        _createPermissionsMap[m.module] = {
          'create': matchedPerm?.create ?? false,
          'read': matchedPerm?.read ?? false,
          'update': matchedPerm?.update ?? false,
          'delete': matchedPerm?.delete ?? false,
        };
      }
    });
  }

  bool _isAllSelected(String moduleCode) {
    final perms = _createPermissionsMap[moduleCode];
    if (perms == null) return false;
    return (perms['create'] ?? false) &&
        (perms['read'] ?? false) &&
        (perms['update'] ?? false) &&
        (perms['delete'] ?? false);
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
      if (!_createPermissionsMap.containsKey(moduleCode)) {
        _createPermissionsMap[moduleCode] = {'create': false, 'read': false, 'update': false, 'delete': false};
      }
      _createPermissionsMap[moduleCode]![type] = value;
    });
  }

  void _submitForm() {
    if (!validateAndScrollToError(_formKey)) return;

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

    if (_isEditing && widget.roleToEdit != null) {
      final roleData = {
        'roleName': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'permissions': permissionsList,
      };
      widget.settingsBloc.add(UpdateRole(widget.roleToEdit!.id, roleData));
    } else {
      final roleCodeVal = _codeController.text.trim().isNotEmpty
          ? _codeController.text.trim().toUpperCase()
          : _nameController.text.trim().toUpperCase().replaceAll(' ', '_');
      final priorityVal = int.tryParse(_priorityController.text.trim()) ?? 5;

      final roleData = {
        'roleName': _nameController.text.trim(),
        'roleCode': roleCodeVal,
        'priority': priorityVal,
        'description': _descController.text.trim(),
        'permissions': permissionsList,
      };
      widget.settingsBloc.add(CreateRole(roleData));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return BlocListener<SettingsBloc, SettingsState>(
      bloc: widget.settingsBloc,
      listener: (context, state) {
        if (state is RoleDetailsLoaded && _isEditing && state.roleDetail.id == widget.roleToEdit?.id) {
          _populateFromRoleDetail(state.roleDetail);
        }
      },
      child: Container(
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
                    Row(
                      children: [
                        Icon(_isEditing ? Icons.edit_note_rounded : Icons.add_circle, color: AppColors.primary, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          _isEditing ? 'Edit Role' : 'Create Role',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary),
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

                        // Role Code & Priority Row
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _codeController,
                                enabled: !_isEditing,
                                decoration: const InputDecoration(
                                  labelText: 'Role Code',
                                  hintText: 'e.g. TELE_CALLER',
                                  labelStyle: TextStyle(color: AppColors.textLabel),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: TextFormField(
                                controller: _priorityController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Priority',
                                  hintText: '5',
                                  labelStyle: TextStyle(color: AppColors.textLabel),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'Priority is required';
                                  if (int.tryParse(val.trim()) == null) return 'Must be number';
                                  return null;
                                },
                              ),
                            ),
                          ],
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
                            final perms = _createPermissionsMap[moduleCode] ??
                                {'create': false, 'read': false, 'update': false, 'delete': false};

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
                                        _buildPanelPermRow(moduleCode, 'Create', 'create', perms['create'] ?? false),
                                        _buildPanelPermRow(moduleCode, 'Read', 'read', perms['read'] ?? false),
                                        _buildPanelPermRow(moduleCode, 'Update', 'update', perms['update'] ?? false),
                                        _buildPanelPermRow(moduleCode, 'Delete', 'delete', perms['delete'] ?? false),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // Submit Button (Update Role / Save Role)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _submitForm,
                            icon: const Icon(Icons.check, size: 18),
                            label: Text(_isEditing ? 'Update Role' : 'Save Role'),
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
