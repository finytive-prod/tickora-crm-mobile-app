import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/staff_bloc.dart';
import 'package:crm_mobile/blocs/staff_event.dart';
import 'package:crm_mobile/blocs/staff_state.dart';
import 'package:crm_mobile/screens/staff/edit_staff_bottom_sheet.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/widgets/confirmation_dialog.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';

class StaffDetailScreen extends StatelessWidget {
  final StaffMember staff;

  const StaffDetailScreen({super.key, required this.staff});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StaffBloc>(),
      child: _StaffDetailView(staff: staff),
    );
  }
}

class _StaffDetailView extends StatefulWidget {
  final StaffMember staff;

  const _StaffDetailView({required this.staff});

  @override
  State<_StaffDetailView> createState() => _StaffDetailViewState();
}

class _StaffDetailViewState extends State<_StaffDetailView> {
  late StaffMember _staff;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _staff = widget.staff;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StaffBloc>().add(FetchStaffDetailEvent(_staff.id));
    });
  }

  Color _avatarColor() {
    final colors = [
      AppColors.primary,
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
    ];
    final index = _staff.fullName.hashCode.abs() % colors.length;
    return colors[index];
  }

  void _handleEdit() {
    EditStaffBottomSheet.show(context, _staff, (data) {
      context.read<StaffBloc>().add(UpdateStaffMemberEvent(id: _staff.id, data: data));
    });
  }

  void _handleToggleStatus() {
    final newActive = !_staff.isActive;
    final action = newActive ? 'Activate' : 'Deactivate';

    ConfirmationDialog.show(
      context,
      title: '$action Staff',
      message: 'Are you sure you want to ${action.toLowerCase()} ${_staff.fullName}?',
      confirmLabel: action,
      isDestructive: !newActive,
      onConfirm: () {
        context.read<StaffBloc>().add(
          ToggleStaffStatusEvent(id: _staff.id, isActive: newActive),
        );
      },
    );
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.trim().isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(rawDate);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return rawDate;
    }
  }

  String _formatDateTime(String? rawDateTime) {
    if (rawDateTime == null || rawDateTime.trim().isEmpty) return 'Never';
    try {
      final dt = DateTime.parse(rawDateTime);
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return rawDateTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor();

    return BlocListener<StaffBloc, StaffState>(
      listener: (context, state) {
        if (state is StaffLoading) {
          setState(() {
            _isLoading = true;
          });
        } else if (state is StaffDetailLoaded) {
          setState(() {
            _staff = state.staffMember;
            _isLoading = false;
          });
        } else if (state is StaffDetailError) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppColors.primary),
          );
        } else if (state is StaffUpdateSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Staff member updated successfully'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
          context.read<StaffBloc>().add(FetchStaffDetailEvent(_staff.id));
        } else if (state is StaffUpdateError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppColors.primary),
          );
        } else if (state is StaffStatusToggled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Staff member ${_staff.isActive ? 'deactivated' : 'activated'} successfully'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          context.read<StaffBloc>().add(FetchStaffDetailEvent(_staff.id));
        } else if (state is StaffStatusToggleError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppColors.primary),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.secondary,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary, size: 20),
            onPressed: () => Navigator.of(context).pop(true),
          ),
          title: const Text(
            'Member Details',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          actions: [
            // Refresh
            IconButton(
              onPressed: () => context.read<StaffBloc>().add(FetchStaffDetailEvent(_staff.id)),
              icon: const Icon(Icons.refresh, color: AppColors.textSecondary, size: 22),
            ),
            // Edit
            if (sl<PrivilegeService>().hasPrivilege('STAFF_UPDATE'))
              IconButton(
                onPressed: _handleEdit,
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 16),
                ),
              ),
            // Toggle Status
            if (sl<PrivilegeService>().hasPrivilege('STAFF_DELETE'))
              IconButton(
                onPressed: _handleToggleStatus,
                icon: Icon(
                  _staff.isActive ? Icons.person_off_outlined : Icons.person_add_alt_1,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            context.read<StaffBloc>().add(FetchStaffDetailEvent(_staff.id));
          },
          child: _isLoading && _staff.email.isEmpty
              ? const Center(child: SpinningLogo(size: 60))
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),

                      // Profile Header Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderEnabled),
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                              backgroundColor: color.withOpacity(0.15),
                              radius: 36,
                              child: Text(
                                _staff.initials,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _staff.fullName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Role Chip
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    _staff.primaryRole,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Account Status Pill
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: _staff.isActive
                                        ? const Color(0xFF10B981).withOpacity(0.12)
                                        : AppColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _staff.isActive ? const Color(0xFF10B981) : AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        _staff.accountStatus.toUpperCase(),
                                        style: TextStyle(
                                          color: _staff.isActive ? const Color(0xFF10B981) : AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Personal Information Section
                      _buildSectionCard(
                        title: 'Personal Information',
                        icon: Icons.person_outline,
                        children: [
                          _buildInfoRow(Icons.badge_outlined, 'Full Name', _staff.fullName),
                          _buildInfoRow(Icons.wc_outlined, 'Gender', _staff.gender ?? 'N/A'),
                          _buildInfoRow(Icons.work_outline, 'Role(s)', _staff.roles.isNotEmpty ? _staff.roles.join(', ') : 'N/A'),
                          _buildInfoRow(Icons.assignment_ind_outlined, 'Designation', _staff.designation ?? 'N/A'),
                          _buildInfoRow(Icons.verified_user_outlined, 'Default User', _staff.isDefault == true ? 'Yes' : 'No'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Work & Contact Details Section
                      _buildSectionCard(
                        title: 'Work & Contact Details',
                        icon: Icons.business_outlined,
                        children: [
                          _buildInfoRowWithBadge(
                            icon: Icons.email_outlined,
                            label: 'Email Address',
                            value: _staff.email.isNotEmpty
                                ? _staff.email
                                : (_staff.username.contains('@') ? _staff.username : 'N/A'),
                            isVerified: _staff.emailVerified,
                          ),
                          _buildInfoRowWithBadge(
                            icon: Icons.phone_outlined,
                            label: 'Phone Number',
                            value: _staff.phone.isNotEmpty ? _staff.phone : 'N/A',
                            isVerified: _staff.phoneVerified,
                          ),
                          _buildInfoRow(Icons.numbers, 'User Code', _staff.userCode.isNotEmpty ? _staff.userCode : 'N/A'),
                          _buildInfoRow(Icons.calendar_today_outlined, 'Date of Joining', _formatDate(_staff.joiningDate)),
                          if (_staff.organizationId != null && _staff.organizationId!.isNotEmpty)
                            _buildInfoRow(Icons.corporate_fare_outlined, 'Organization ID', _staff.organizationId!),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Account & Activity Section
                      _buildSectionCard(
                        title: 'Account Activity & Timestamps',
                        icon: Icons.history_outlined,
                        children: [
                          _buildInfoRow(Icons.toggle_on_outlined, 'Account Status', _staff.accountStatus),
                          _buildInfoRow(Icons.add_circle_outline, 'Created At', _formatDateTime(_staff.createdAt)),
                          _buildInfoRow(Icons.update_outlined, 'Updated At', _formatDateTime(_staff.updatedAt)),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ),
      
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRowWithBadge({
    required IconData icon,
    required String label,
    required String value,
    required bool isVerified,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
