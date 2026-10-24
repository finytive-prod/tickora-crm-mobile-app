import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/utils/whatsapp_helper.dart';

class WhatsAppOutreachModal extends StatefulWidget {
  final String leadName;
  final String phone;
  final String company;
  final String? leadId;

  const WhatsAppOutreachModal({
    super.key,
    required this.leadName,
    required this.phone,
    this.company = '',
    this.leadId,
  });

  static Future<void> show(
    BuildContext context, {
    required String leadName,
    required String phone,
    String company = '',
    String? leadId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WhatsAppOutreachModal(
        leadName: leadName,
        phone: phone,
        company: company,
        leadId: leadId,
      ),
    );
  }

  @override
  State<WhatsAppOutreachModal> createState() => _WhatsAppOutreachModalState();
}

class _WhatsAppOutreachModalState extends State<WhatsAppOutreachModal> {
  late TextEditingController _messageController;
  int _selectedTemplateIndex = 0;

  static const List<Map<String, String>> templates = [
    {
      'title': 'Welcome & Intro',
      'category': 'Outreach',
      'body':
          'Hi {{firstName}}, this is from our CRM team. Thank you for reaching out! I noticed you are exploring our solutions for {{company}}. Would you have 5 minutes for a quick chat today?',
    },
    {
      'title': 'Post-Demo Follow-Up',
      'category': 'Follow-Up',
      'body':
          'Hi {{firstName}}, thank you for joining our walkthrough today! As discussed, our solution will save {{company}} hours every week. Would you like me to share the onboarding summary?',
    },
    {
      'title': 'Special Incentive',
      'category': 'Closing',
      'body':
          'Hello {{firstName}}, hope your week is going great! We just finalized a special commercial plan for {{company}}. Would you like to review the agreement this afternoon?',
    },
    {
      'title': 'Meeting Reminder',
      'category': 'Scheduling',
      'body':
          'Hi {{firstName}}, quick reminder about our call today regarding {{company}}. Looking forward to speaking with you! Please let me know if you need to adjust the timing.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      text: _getInterpolatedText(templates[0]['body']!),
    );
  }

  String _getInterpolatedText(String template) {
    final firstName = widget.leadName.trim().split(' ').first;
    return WhatsAppHelper.interpolate(template, {
      'firstName': firstName,
      'name': widget.leadName,
      'company': widget.company.isNotEmpty ? widget.company : 'your company',
      'agentName': 'Our Team',
    });
  }

  void _onTemplateSelected(int index) {
    setState(() {
      _selectedTemplateIndex = index;
      _messageController.text = _getInterpolatedText(templates[index]['body']!);
    });
  }

  Future<void> _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    Navigator.pop(context);

    final success = await WhatsAppHelper.openWhatsApp(
      context,
      phoneNumber: widget.phone,
      message: text,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp opened & message copied to clipboard!'),
          backgroundColor: Color(0xFF128C7E),
        ),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: bottomInset + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: Color(0xFF25D366),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhatsApp to ${widget.leadName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      widget.phone,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Template Chips
          const Text(
            'SELECT TEMPLATE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(templates.length, (i) {
                final isSelected = _selectedTemplateIndex == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(templates[i]['title']!),
                    selected: isSelected,
                    selectedColor: const Color(0xFFDCF8C6),
                    backgroundColor: Colors.grey.shade100,
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF075E54) : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (val) => _onTemplateSelected(i),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // Editable Message Bubble
          TextField(
            controller: _messageController,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: InputDecoration(
              labelText: 'Message (editable)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
            ),
          ),
          const SizedBox(height: 14),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text(
                'Open WhatsApp & Send',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: _handleSend,
            ),
          ),
        ],
      ),
    );
  }
}
