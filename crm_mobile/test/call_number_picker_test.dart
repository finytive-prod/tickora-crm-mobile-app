import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/models/follow_up.dart';
import 'package:crm_mobile/models/lead.dart';
import 'package:crm_mobile/models/lead_detail.dart';
import 'package:crm_mobile/widgets/call_number_picker_sheet.dart';
import 'package:crm_mobile/widgets/lead_card.dart';

void main() {
  tearDown(() {
    AutoCallRecordingUploader.invalidatePhoneLookupCache();
  });

  group('Lead & FollowUp alternatePhone parsing', () {
    test('LeadModel.fromJson parses direct and fallback alternatePhone keys', () {
      final leadDirect = LeadModel.fromJson({
        'id': 'lead-1',
        'firstName': 'Aarav',
        'lastName': 'Sharma',
        'phone': '+91 98765 43210',
        'alternatePhone': '+91 91234 56789',
      });
      expect(leadDirect.phone, '+91 98765 43210');
      expect(leadDirect.alternatePhone, '+91 91234 56789');

      final leadAlt = LeadModel.fromJson({
        'id': 'lead-2',
        'phone': '9876543210',
        'alternativePhone': '9000011111',
      });
      expect(leadAlt.alternatePhone, '9000011111');

      final leadCustom = LeadModel.fromJson({
        'id': 'lead-3',
        'phone': '9876543210',
        'customFields': [
          {
            'fieldId': 'cf-1',
            'fieldName': 'altPhone',
            'label': 'Alternate Mobile',
            'fieldType': 'phone',
            'value': '9988776655',
          },
        ],
      });
      expect(leadCustom.alternatePhone, '9988776655');
    });

    test('FollowUpModel.fromJson parses direct and nested lead alternatePhone', () {
      final directFollowUp = FollowUpModel.fromJson({
        'id': 'fu-1',
        'leadId': 'lead-1',
        'leadName': 'Aarav Sharma',
        'phoneNumber': '9876543210',
        'alternatePhone': '9123456789',
      });
      expect(directFollowUp.phoneNumber, '9876543210');
      expect(directFollowUp.alternatePhone, '9123456789');

      final nestedFollowUp = FollowUpModel.fromJson({
        'id': 'fu-2',
        'leadId': 'lead-2',
        'lead': {
          'firstName': 'Priya',
          'lastName': 'Nair',
          'phone': '9876500000',
          'alternatePhone': '9876599999',
        },
      });
      expect(nestedFollowUp.phoneNumber, '9876500000');
      expect(nestedFollowUp.alternatePhone, '9876599999');
    });
  });

  group('Phone option normalization and deduplication', () {
    test('returns two distinct options for primary and alternate numbers', () {
      final options = buildDistinctLeadPhoneOptions(
        primaryPhone: '+91 98765 43210',
        alternatePhone: '+91 91234 56789',
      );
      expect(options.length, 2);
      expect(options[0].label, 'Primary Number');
      expect(options[0].phoneNumber, '+91 98765 43210');
      expect(options[0].isAlternate, isFalse);
      expect(options[1].label, 'Alternate Number');
      expect(options[1].phoneNumber, '+91 91234 56789');
      expect(options[1].isAlternate, isTrue);
    });

    test('deduplicates formatted variants of the same phone number', () {
      final options = buildDistinctLeadPhoneOptions(
        primaryPhone: '+91 98765 43210',
        alternatePhone: '9876543210',
      );
      expect(options.length, 1);
      expect(options.first.phoneNumber, '+91 98765 43210');
    });

    test('handles alternate-only lead and ignores placeholders', () {
      final options = buildDistinctLeadPhoneOptions(
        primaryPhone: '-',
        alternatePhone: '9123456789',
      );
      expect(options.length, 1);
      expect(options.first.label, 'Alternate Number');
      expect(options.first.phoneNumber, '9123456789');
    });

    test('extractLeadDetailCustomPhoneOptions captures additional phone fields', () {
      final extra = extractLeadDetailCustomPhoneOptions(const [
        LeadDetailCustomField(
          fieldId: '1',
          fieldName: 'officePhone',
          label: 'Office Mobile',
          fieldType: 'phone',
          value: '9811122233',
        ),
        LeadDetailCustomField(
          fieldId: '2',
          fieldName: 'city',
          label: 'City',
          fieldType: 'text',
          value: 'Chennai',
        ),
      ]);
      expect(extra.length, 1);
      expect(extra.first.label, 'Office Mobile');
      expect(extra.first.phoneNumber, '9811122233');
    });
  });

  group('AutoCallRecordingUploader dual-phone cache', () {
    test('caches both primary and alternate phones and preserves detail resolution', () {
      const detail = LeadDetail(
        id: 'lead-100',
        leadNumber: 'LD-100',
        firstName: 'Kiran',
        lastName: 'Patel',
        companyName: 'Acme',
        email: 'kiran@example.com',
        phone: '9876543210',
        alternatePhone: '9123456789',
      );
      AutoCallRecordingUploader.registerKnownLeads([detail]);

      expect(AutoCallRecordingUploader.hasResolvedLeadDetailPhones('lead-100'), isTrue);
      final record = AutoCallRecordingUploader.getCachedLeadPhoneRecord('lead-100');
      expect(record, isNotNull);
      expect(record!.primaryPhone, '9876543210');
      expect(record.alternatePhone, '9123456789');

      // Summary lead refresh without alternatePhone must not overwrite cached alternatePhone.
      const summaryLead = Lead(
        id: 'lead-100',
        leadNumber: 'LD-100',
        firstName: 'Kiran',
        lastName: 'Patel',
        companyName: 'Acme',
        email: 'kiran@example.com',
        phone: '9876543210',
      );
      AutoCallRecordingUploader.registerKnownLeads([summaryLead]);

      final merged = AutoCallRecordingUploader.getCachedLeadPhoneRecord('lead-100');
      expect(merged!.alternatePhone, '9123456789');
      expect(AutoCallRecordingUploader.hasResolvedLeadDetailPhones('lead-100'), isTrue);
    });
  });

  group('Pre-call confirmation dialog behavior', () {
    Widget wrapForTest(Widget child) {
      return MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Scaffold(body: child),
      );
    }

    testWidgets('prompts user to choose between two numbers and dials selected number', (tester) async {
      String? dialedNumber;

      await tester.pumpWidget(
        wrapForTest(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                LeadCallHelper.initiateLeadCall(
                  context: context,
                  leadId: 'lead-1',
                  primaryPhone: '9876543210',
                  alternatePhone: '9123456789',
                  leadName: 'Aarav Sharma',
                  onDial: (selected) async {
                    dialedNumber = selected;
                  },
                );
              },
              child: const Text('Call Lead'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call Lead'));
      await tester.pumpAndSettle();

      // Confirmation dialog must ask before calling.
      expect(find.text('Select Number to Call'), findsOneWidget);
      expect(find.text('Primary Number'), findsOneWidget);
      expect(find.text('Alternate Number'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('9123456789'), findsOneWidget);
      expect(dialedNumber, isNull);

      // Selecting Alternate Number confirms and dials it.
      await tester.tap(find.text('9123456789'));
      await tester.pumpAndSettle();

      expect(dialedNumber, '9123456789');
      expect(find.text('Select Number to Call'), findsNothing);
    });

    testWidgets('cancelling number confirmation dialog does not place a call', (tester) async {
      String? dialedNumber;

      await tester.pumpWidget(
        wrapForTest(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                LeadCallHelper.initiateLeadCall(
                  context: context,
                  leadId: 'lead-1',
                  primaryPhone: '9876543210',
                  alternatePhone: '9123456789',
                  leadName: 'Aarav Sharma',
                  onDial: (selected) async {
                    dialedNumber = selected;
                  },
                );
              },
              child: const Text('Call Lead'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call Lead'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(dialedNumber, isNull);
    });

    testWidgets('calls directly without confirmation dialog when lead has only one number', (tester) async {
      String? dialedNumber;

      await tester.pumpWidget(
        wrapForTest(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                LeadCallHelper.initiateLeadCall(
                  context: context,
                  leadId: 'lead-1',
                  primaryPhone: '9876543210',
                  alternatePhone: '+91 98765 43210', // Same number formatted
                  leadName: 'Aarav Sharma',
                  onDial: (selected) async {
                    dialedNumber = selected;
                  },
                );
              },
              child: const Text('Call Lead'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Call Lead'));
      await tester.pumpAndSettle();

      expect(find.text('Select Number to Call'), findsNothing);
      expect(dialedNumber, '9876543210');
    });

    testWidgets('LeadCard opens confirmation dialog when lead has alternatePhone', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          const LeadCard(
            leadId: 'lead-card-1',
            leadNumber: 'LD-1',
            initials: 'AS',
            name: 'Aarav Sharma',
            company: 'Acme',
            status: 'New',
            statusBgColor: Colors.blueAccent,
            statusTextColor: Colors.blue,
            priority: 'High Priority',
            priorityColor: Colors.red,
            assignee: 'Admin',
            phone: '9876543210',
            alternatePhone: '9123456789',
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.phone));
      await tester.pumpAndSettle();

      expect(find.byType(CallNumberPickerDialog), findsOneWidget);
      expect(find.text('Select Number to Call'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CallNumberPickerDialog),
          matching: find.text('9876543210'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(CallNumberPickerDialog),
          matching: find.text('9123456789'),
        ),
        findsOneWidget,
      );
    });
  });
}

