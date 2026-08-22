import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/staff_member.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/blocs/staff_bloc.dart';
import 'package:crm_mobile/blocs/staff_event.dart';
import 'package:crm_mobile/blocs/staff_state.dart';
import 'package:crm_mobile/screens/staff/edit_staff_bottom_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _staff = widget.staff;
  }

  Color _avatarColor() {
    final colors = [
      const Color(0xFFEF4444),
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

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              newActive ? Icons.check_circle_outline : Icons.block,
              color: newActive ? const Color(0xFF10B981) : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '$action Staff',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to ${action.toLowerCase()} ${_staff.fullName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newActive ? const Color(0xFF10B981) : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<StaffBloc>().add(
                ToggleStaffStatusEvent(id: _staff.id, isActive: newActive),
              );
            },
            child: Text(action, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _avatarColor();

    return BlocListener<StaffBloc, StaffState>(
      listener: (context, state) {
        if (state is StaffUpdateSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Staff member updated successfully'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
          Navigator.of(context).pop(true); // Return true to trigger refresh
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
          Navigator.of(context).pop(true);
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
            onPressed: () => Navigator.of(context).pop(),
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
            // Edit
            IconButton(
              onPressed: _handleEdit,
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit, color: Colors.white, size: 16),
              ),
            ),
            // Toggle Status
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
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
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
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Personal Information
              _buildSectionCard(
                title: 'Personal Information',
                icon: Icons.person_outline,
                children: [
                  _buildInfoRow(Icons.badge_outlined, 'Full Name', _staff.fullName),
                  _buildInfoRow(Icons.wc_outlined, 'Gender', _staff.gender ?? 'N/A'),
                  _buildInfoRow(Icons.work_outline, 'Role', _staff.primaryRole),
                  _buildInfoRow(Icons.assignment_ind_outlined, 'Designation', _staff.designation ?? 'N/A'),
                ],
              ),
              const SizedBox(height: 16),

              // Work & Contact Details
              _buildSectionCard(
                title: 'Work & Contact Details',
                icon: Icons.business_outlined,
                children: [
                  _buildInfoRow(Icons.email_outlined, 'Email Address', _staff.email),
                  _buildInfoRow(Icons.phone_outlined, 'Phone Number', _staff.phone),
                  _buildInfoRow(Icons.calendar_today_outlined, 'Date of Joining', _staff.joiningDate ?? 'N/A'),
                  _buildInfoRow(Icons.numbers, 'User Code', _staff.userCode),
                ],
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 24),

              // Activate/Deactivate Button
              
              const SizedBox(height: 24),
            ],
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
}
