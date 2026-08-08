import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'leads/leads_screen.dart';
import 'more/more_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // Default to Leads tab

  final List<Widget> _screens = [
    const Center(child: Text('Dashboard Coming Soon', style: TextStyle(fontSize: 18))),
    const LeadsScreen(),
    const Center(child: Text('Tasks Coming Soon', style: TextStyle(fontSize: 18))),
    const Center(child: Text('Calendar Coming Soon', style: TextStyle(fontSize: 18))),
    const MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
