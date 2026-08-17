import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/screens/calendar/add_event_screen.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/calendar_bloc.dart';
import 'package:crm_mobile/blocs/calendar_event.dart';
import 'package:crm_mobile/blocs/calendar_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/models/calendar_event_model.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return sl<CalendarBloc>()
          ..add(FetchCalendarCategories())
          ..add(FetchCalendarEvents(start: start, end: end));
      },
      child: const CalendarScreenView(),
    );
  }
}

class CalendarScreenView extends StatefulWidget {
  const CalendarScreenView({super.key});

  @override
  State<CalendarScreenView> createState() => _CalendarScreenViewState();
}

class _CalendarScreenViewState extends State<CalendarScreenView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String _selectedTab = 'Month';
  List<CalendarEventModel> _events = [];
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  List<CalendarEventModel> _getEventsForDay(DateTime day) {
    return _events.where((e) => isSameDay(e.startTime, day)).toList();
  }

  void _showEventsBottomSheet(BuildContext context, DateTime day, List<CalendarEventModel> events) {
    final bloc = context.read<CalendarBloc>();
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: 5),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('EEEE, MMM dd, yyyy').format(day),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textHint),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: events.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (ctx, index) {
                      final event = events[index];
                      final color = _getCategoryColor(event.category);
                      final start = DateFormat('hh:mm a').format(event.startTime);
                      final end = event.endTime != null ? DateFormat('hh:mm a').format(event.endTime!) : '';
                      final timeStr = end.isEmpty ? start : '$start - $end';
                      
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderEnabled),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    event.category,
                                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => BlocProvider.value(value: bloc, child: AddEventScreen(eventId: event.id, initialData: event.toJson()))));
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
                                        child: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        bloc.add(DeleteCalendarEvent(event.id));
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
                                        child: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(event.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 16, color: AppColors.textHint),
                                const SizedBox(width: 8),
                                Text(timeStr, style: const TextStyle(fontSize: 14, color: AppColors.textLabel)),
                              ],
                            ),
                            if (event.location != null && event.location!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textHint),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(event.location!, style: const TextStyle(fontSize: 14, color: AppColors.textLabel))),
                                ],
                              ),
                            ],
                            if (event.description != null && event.description!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.borderEnabled),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.notes, size: 16, color: AppColors.textHint),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(event.description!, style: const TextStyle(fontSize: 13, color: AppColors.textLabel))),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: bloc,
                            child: AddEventScreen(initialData: {
                              'startTime': day.toIso8601String(),
                              'endTime': day.add(const Duration(hours: 1)).toIso8601String(),
                            }),
                          ),
                        ),
                      );
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 20),
                        SizedBox(width: 8),
                        Text('Create New Event', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterTab(String label, {bool isSelected = false, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.red : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textLabel,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Calendar',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: BlocListener<CalendarBloc, CalendarState>(
          listener: (context, state) {
            if (state is CalendarEventsLoaded) {
              setState(() {
                _events = state.events.cast<CalendarEventModel>();
              });
            } else if (state is CalendarCategoriesLoaded) {
              setState(() {
                _categories = state.categories;
              });
            } else if (state is CalendarActionSuccess) {
              final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
              final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);
              context.read<CalendarBloc>().add(FetchCalendarEvents(start: start, end: end));
            }
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildFilterTab('Month', isSelected: _selectedTab == 'Month', onTap: () => setState(() => _selectedTab = 'Month')),
                      _buildFilterTab('Week', isSelected: _selectedTab == 'Week', onTap: () => setState(() => _selectedTab = 'Week')),
                      _buildFilterTab('Day', isSelected: _selectedTab == 'Day', onTap: () => setState(() => _selectedTab = 'Day')),
                      _buildFilterTab('Agenda', isSelected: _selectedTab == 'Agenda', onTap: () => setState(() => _selectedTab = 'Agenda')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Content
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: context.read<CalendarBloc>(),
                child: const AddEventScreen(),
              ),
            ),
          );
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedTab) {
      case 'Month':
        return _buildMonthView();
      case 'Week':
        return _buildWeekView();
      case 'Day':
        return _buildDayView();
      case 'Agenda':
        return _buildAgendaView();
      default:
        return _buildMonthView();
    }
  }

  // ===================== MONTH VIEW =====================
  Widget _buildMonthView() {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: CalendarFormat.month,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          eventLoader: _getEventsForDay,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
            final eventsForDay = _getEventsForDay(selectedDay);
            if (eventsForDay.isEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: context.read<CalendarBloc>(),
                    child: AddEventScreen(initialData: {
                      'startTime': selectedDay.toIso8601String(),
                      'endTime': selectedDay.add(const Duration(hours: 1)).toIso8601String(),
                    }),
                  ),
                ),
              );
            } else {
              _showEventsBottomSheet(context, selectedDay, eventsForDay);
            }
          },
          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
            final start = DateTime(focusedDay.year, focusedDay.month, 1);
            final end = DateTime(focusedDay.year, focusedDay.month + 1, 0, 23, 59, 59);
            context.read<CalendarBloc>().add(FetchCalendarEvents(start: start, end: end));
          },
          calendarStyle: const CalendarStyle(
            selectedDecoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(color: AppColors.textHint, shape: BoxShape.circle),
            markerDecoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          ),
          headerVisible: false,
          daysOfWeekStyle: const DaysOfWeekStyle(
            weekdayStyle: TextStyle(color: AppColors.textHint, fontSize: 12),
            weekendStyle: TextStyle(color: AppColors.textHint, fontSize: 12),
          ),
        ),
        const Divider(),
        Expanded(
          child: Container(
            color: AppColors.secondary,
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EVENT CATEGORIES',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textLabel),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _categories.isEmpty 
                      ? const Center(child: Text('No categories found.'))
                      : GridView.count(
                          shrinkWrap: true,
                          crossAxisCount: 3,
                          childAspectRatio: 2.5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          children: _categories.map((category) {
                            return _buildCategoryCheckbox(category, _getCategoryColor(category));
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toUpperCase()) {
      case 'EVENT':
        return Colors.blue;
      case 'MEETING':
        return Colors.purple;
      case 'TASK':
        return Colors.green;
      case 'CALL':
        return Colors.lightBlue;
      case 'REMINDER':
        return Colors.orange;
      case 'BIRTHDAY':
        return Colors.pink;
      case 'FOLLOW_UP':
      case 'FOLLOW UP':
        return Colors.red;
      default:
        return AppColors.primary;
    }
  }

  Widget _buildCategoryCheckbox(String label, Color dotColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_box, color: Colors.red, size: 18),
          const SizedBox(width: 4),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // ===================== WEEK VIEW =====================
  Widget _buildWeekView() {
    int daysToSubtract = _focusedDay.weekday - 1;
    DateTime startOfWeek = _focusedDay.subtract(Duration(days: daysToSubtract));
    DateTime endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
    
    final weekEvents = _events.where((e) => 
      e.startTime.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) && 
      e.startTime.isBefore(endOfWeek.add(const Duration(seconds: 1)))
    ).toList();
    
    if (weekEvents.isEmpty) {
      return const Center(child: Text('No events for this week'));
    }
    
    weekEvents.sort((a, b) => a.startTime.compareTo(b.startTime));
    
    final Map<String, List<CalendarEventModel>> grouped = {};
    for (final event in weekEvents) {
      final dateStr = DateFormat('yyyy-MM-dd').format(event.startTime);
      grouped.putIfAbsent(dateStr, () => []).add(event);
    }
    
    final List<Widget> items = [];
    final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    for (final dateStr in grouped.keys) {
      final date = DateTime.parse(dateStr);
      final isToday = dateStr == nowStr;
      
      String headerTitle = '';
      if (isToday) {
        headerTitle = 'Today, ${DateFormat('MMM dd').format(date)}';
      } else {
        headerTitle = DateFormat('EEEE, MMM dd').format(date);
      }
      
      items.add(Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
        child: _buildAgendaSectionHeader(headerTitle, isToday: isToday),
      ));
      
      final dayEvents = grouped[dateStr]!;
      for (int i = 0; i < dayEvents.length; i++) {
        final event = dayEvents[i];
        final start = DateFormat('hh:mm a').format(event.startTime);
        final end = event.endTime != null ? DateFormat('hh:mm a').format(event.endTime!) : '';
        final timeStr = end.isEmpty ? start : '$start - $end';
        final color = _getCategoryColor(event.category);
        
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _buildDayCard(
            event.category,
            'Event',
            event.title,
            timeStr,
            event.location ?? '',
            color,
            color.withValues(alpha: 0.1),
            onTap: () => _showEventsBottomSheet(context, event.startTime, [event])
          ),
        ));
      }
    }

    return Container(
      color: AppColors.secondary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: items,
      ),
    );
  }





  // ===================== DAY VIEW =====================
  Widget _buildDayView() {
    final eventsToday = _getEventsForDay(_focusedDay);
    if (eventsToday.isEmpty) {
      return const Center(child: Text('No events for this day'));
    }
    
    return Container(
      color: AppColors.secondary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: eventsToday.length,
        itemBuilder: (context, index) {
          final event = eventsToday[index];
          final start = DateFormat('hh:mm a').format(event.startTime);
          final end = event.endTime != null ? DateFormat('hh:mm a').format(event.endTime!) : '';
          final timeStr = end.isEmpty ? start : '$start - $end';
          final color = _getCategoryColor(event.category);
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _buildDayCard(
              event.category, 
              'Event', 
              event.title, 
              timeStr, 
              event.location ?? '', 
              color, 
              color.withValues(alpha: 0.1),
              onTap: () => _showEventsBottomSheet(context, event.startTime, [event])
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayCard(String category, String duration, String title, String time, String location, Color color, Color bgColor, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
                          child: Text(category, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(12)),
                          child: Text(duration, style: const TextStyle(color: AppColors.textLabel, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(time, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                        const SizedBox(width: 12),
                        const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textHint),
                        const SizedBox(width: 4),
                        Text(location, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  // ===================== AGENDA VIEW =====================
  Widget _buildAgendaView() {
    if (_events.isEmpty) {
      return const Center(child: Text('No upcoming events'));
    }
    
    // Sort events
    final sortedEvents = List<CalendarEventModel>.from(_events)..sort((a, b) => a.startTime.compareTo(b.startTime));
    
    // Group by date string (e.g. "yyyy-MM-dd")
    final Map<String, List<CalendarEventModel>> grouped = {};
    for (final event in sortedEvents) {
      final dateStr = DateFormat('yyyy-MM-dd').format(event.startTime);
      grouped.putIfAbsent(dateStr, () => []).add(event);
    }
    
    final List<Widget> items = [];
    final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    for (final dateStr in grouped.keys) {
      final date = DateTime.parse(dateStr);
      final isToday = dateStr == nowStr;
      
      String headerTitle = '';
      if (isToday) {
        headerTitle = 'Today, ${DateFormat('MMM dd').format(date)}';
      } else {
        headerTitle = DateFormat('EEEE, MMM dd').format(date);
      }
      
      items.add(_buildAgendaSectionHeader(headerTitle, isToday: isToday));
      
      final dayEvents = grouped[dateStr]!;
      for (int i = 0; i < dayEvents.length; i++) {
        final event = dayEvents[i];
        final timeStr = DateFormat('hh:mm a').format(event.startTime);
        items.add(_buildAgendaItem(
          event.title, 
          timeStr, 
          event.location ?? '', 
          _getCategoryColor(event.category), 
          i < dayEvents.length - 1, // hasNext
          onTap: () => _showEventsBottomSheet(context, event.startTime, [event])
        ));
      }
      items.add(const SizedBox(height: 16));
    }

    return Container(
      color: AppColors.secondary,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: items,
      ),
    );
  }

  Widget _buildAgendaSectionHeader(String title, {bool isToday = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
          if (isToday) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: const Text('TODAY', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildAgendaItem(String title, String time, String location, Color color, bool hasNext, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                if (hasNext) Expanded(child: Container(width: 1, color: AppColors.borderEnabled)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(time, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                        const SizedBox(width: 8),
                        const Text('•', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                        const SizedBox(width: 8),
                        Text(location, style: const TextStyle(fontSize: 12, color: AppColors.textHint)),
                      ],
                    ),
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
}
