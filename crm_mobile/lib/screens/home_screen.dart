import 'package:flutter/material.dart';
import 'package:crm_mobile/widgets/custom_bottom_nav_bar.dart';
import 'package:crm_mobile/screens/leads/leads_screen.dart';
import 'package:crm_mobile/screens/more/more_screen.dart';
import 'package:crm_mobile/screens/followups/followups_screen.dart';
import 'package:crm_mobile/screens/calendar/calendar_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // Default to Leads tab

  void changeTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  final List<Widget> _screens = [
    const Center(child: Text('Dashboard Coming Soon', style: TextStyle(fontSize: 18))),
    const LeadsScreen(),
    const FollowUpsScreen(),
    const CalendarScreen(),
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
