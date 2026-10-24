import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/screens/leads/add_lead_screen.dart';
import 'package:crm_mobile/screens/leads/quick_invite_screen.dart';
import 'package:crm_mobile/widgets/in_app_dialpad_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/injection/injection.dart';

class ExpandableFab extends StatefulWidget {
  const ExpandableFab({super.key});

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab> with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: 0.0,
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeOutQuad,
      parent: _controller,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _navigateTo(Widget screen) {
    _toggle();
    final bloc = context.read<LeadsBloc>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider<LeadsBloc>.value(
          value: bloc,
          child: screen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final priv = sl<PrivilegeService>();
    final canCreateLead = priv.hasPrivilege('LEAD_CREATE');
    final canUseDialer = priv.hasPrivilege('CALL_READ') || priv.hasPrivilege('DASHBOARD_READ') || priv.hasPrivilege('LEAD_READ');

    if (!canCreateLead && !canUseDialer) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (canCreateLead) ...[
          SizeTransition(
            sizeFactor: _expandAnimation,
            axisAlignment: 1.0, // Expand upwards from the bottom
            child: Align(
              alignment: Alignment.bottomRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(height: 12),
                  _buildActionItem(
                    label: 'Quick Invite',
                    icon: Icons.flash_on,
                    color: Colors.orange,
                    onTap: () => _navigateTo(const QuickInviteScreen()),
                  ),
                  const SizedBox(height: 12),
                  _buildActionItem(
                    label: 'Add Single Lead',
                    icon: Icons.person_add,
                    color: AppColors.primary,
                    onTap: () => _navigateTo(const AddLeadScreen()),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          FloatingActionButton(
            heroTag: 'expandable_fab_main',
            backgroundColor: AppColors.primary,
            shape: const CircleBorder(),
            onPressed: _toggle,
            child: AnimatedIcon(
              icon: AnimatedIcons.menu_close,
              progress: _controller,
              color: Colors.white,
            ),
          ),
          if (canUseDialer) const SizedBox(height: 12),
        ],
        if (canUseDialer)
          FloatingActionButton(
            heroTag: 'dialer_fab_under_3_line',
            backgroundColor: Colors.teal,
            shape: const CircleBorder(),
            onPressed: () {
              final bloc = context.read<LeadsBloc>();
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (modalContext) => BlocProvider<LeadsBloc>.value(
                  value: bloc,
                  child: const InAppDialpadBottomSheet(),
                ),
              );
            },
            child: const Icon(Icons.dialpad, color: Colors.white, size: 24),
          ),
      ],
    );
  }

  Widget _buildActionItem({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56, // Match main FAB width to center
            alignment: Alignment.center,
            child: FloatingActionButton(
              heroTag: label,
              mini: true,
              backgroundColor: color,
              shape: const CircleBorder(),
              onPressed: onTap,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
