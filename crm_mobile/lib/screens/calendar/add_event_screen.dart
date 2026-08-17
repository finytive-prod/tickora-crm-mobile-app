import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/custom_text_field.dart';
import 'package:crm_mobile/widgets/custom_dropdown_field.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/calendar_bloc.dart';
import 'package:crm_mobile/blocs/calendar_state.dart';
import 'package:intl/intl.dart';
import 'package:crm_mobile/blocs/calendar_event.dart';

class AddEventScreen extends StatefulWidget {
  final String? eventId;
  final Map<String, dynamic>? initialData;

  const AddEventScreen({super.key, this.eventId, this.initialData});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final _titleController = TextEditingController();
  final _dateController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  
  String? _selectedCategory = 'Meeting';

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      final data = widget.initialData!;
      _titleController.text = data['title'] ?? '';
      _notesController.text = data['description'] ?? '';
      _locationController.text = data['location'] ?? '';
      _selectedCategory = data['category'] ?? 'MEETING';
      
      try {
        if (data['startTime'] != null) {
          final start = DateTime.parse(data['startTime']);
          _dateController.text = DateFormat('MMM d, yyyy').format(start);
          _startTimeController.text = DateFormat('h:mm a').format(start);
        }
        if (data['endTime'] != null) {
          final end = DateTime.parse(data['endTime']);
          _endTimeController.text = DateFormat('h:mm a').format(end);
        }
      } catch (e) {
        // Date parsing fallback
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _dateController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      setState(() {
        _dateController.text = '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
      });
    }
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      setState(() {
        controller.text = '${hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} $period';
      });
    }
  }

  void _saveEvent() {
    if (_titleController.text.isEmpty || _dateController.text.isEmpty || 
        _startTimeController.text.isEmpty || _endTimeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill required fields')));
      return;
    }

    try {
      final date = DateFormat('MMM d, yyyy').parse(_dateController.text);
      final startTime = DateFormat('h:mm a').parse(_startTimeController.text);
      final endTime = DateFormat('h:mm a').parse(_endTimeController.text);

      final startDateTime = DateTime(date.year, date.month, date.day, startTime.hour, startTime.minute);
      final endDateTime = DateTime(date.year, date.month, date.day, endTime.hour, endTime.minute);

      final data = {
        "title": _titleController.text,
        "description": _notesController.text,
        "startTime": startDateTime.toIso8601String(),
        "endTime": endDateTime.toIso8601String(),
        "category": _selectedCategory ?? 'EVENT',
        "location": _locationController.text,
      };

      if (widget.eventId != null) {
        context.read<CalendarBloc>().add(UpdateCalendarEvent(widget.eventId!, data));
      } else {
        context.read<CalendarBloc>().add(CreateCalendarEvent(data));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid date/time format')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CalendarBloc, CalendarState>(
      listener: (context, state) {
        if (state is CalendarActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          Navigator.pop(context);
        } else if (state is CalendarActionFailure) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.secondary,
      appBar: AppBar(
        title: const Text('New Event', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextField(
                label: 'Event Title',
                controller: _titleController,
                hintText: 'Enter event title',
                isRequired: true,
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickDate,
                child: AbsorbPointer(
                  child: CustomTextField(
                    label: 'Date',
                    controller: _dateController,
                    hintText: 'Select Date',
                    isRequired: true,
                    suffixIcon: const Icon(Icons.calendar_today_outlined, color: AppColors.textHint, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _pickTime(_startTimeController),
                      child: AbsorbPointer(
                        child: CustomTextField(
                          label: 'Start Time',
                          controller: _startTimeController,
                          hintText: 'HH:MM',
                          isRequired: true,
                          suffixIcon: const Icon(Icons.access_time, color: AppColors.textHint, size: 20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _pickTime(_endTimeController),
                      child: AbsorbPointer(
                        child: CustomTextField(
                          label: 'End Time',
                          controller: _endTimeController,
                          hintText: 'HH:MM',
                          isRequired: true,
                          suffixIcon: const Icon(Icons.access_time, color: AppColors.textHint, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BlocBuilder<CalendarBloc, CalendarState>(
                builder: (context, state) {
                  List<DropdownMenuItem<String>> items = [];
                  if (state is CalendarCategoriesLoaded) {
                    items = state.categories.map((category) {
                      return DropdownMenuItem(value: category, child: Text(category));
                    }).toList();
                  } else {
                    items = [
                      const DropdownMenuItem(value: 'Loading...', child: Text('Loading...')),
                    ];
                  }

                  return CustomDropdownField<String>(
                    label: 'Category',
                    value: _selectedCategory != null && items.any((i) => i.value == _selectedCategory) 
                        ? _selectedCategory 
                        : null,
                    items: items,
                    onChanged: (val) {
                      setState(() {
                        _selectedCategory = val;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              CustomTextField(
                label: 'Location',
                controller: _locationController,
                hintText: 'Enter location',
              ),
              const SizedBox(height: 16),
              
              CustomTextField(
                label: 'Agenda Notes',
                controller: _notesController,
                hintText: 'Key discussion points on pricing, terms, deliverables.',
                maxLines: 4,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: BlocBuilder<CalendarBloc, CalendarState>(
                  builder: (context, state) {
                    if (state is CalendarActionLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return ElevatedButton(
                      onPressed: _saveEvent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(widget.eventId != null ? 'Update Event' : 'Save Event', style: const TextStyle(fontSize: 16, color: Colors.white)),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
