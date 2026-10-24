import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/screens/leads/quick_invite_screen.dart';
import 'package:crm_mobile/core/services/auto_call_recording_uploader.dart';
import 'package:crm_mobile/core/services/direct_call_helper.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/repositories/leads_repository.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/utils/phone_number_utils.dart';

class InAppDialpadBottomSheet extends StatefulWidget {
  const InAppDialpadBottomSheet({super.key});

  @override
  State<InAppDialpadBottomSheet> createState() => _InAppDialpadBottomSheetState();
}

class _InAppDialpadBottomSheetState extends State<InAppDialpadBottomSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  String get _phoneNumber => _phoneController.text;
  
  // UI Details for Matched Lead
  String _matchedLeadId = '';
  String _leadName = '--';
  String _leadInitial = '';
  String _leadAssignee = '--';
  String _leadSource = '';
  String _leadStatus = '';
  String? _leadStatusColor;
  bool _isMatched = false;
  bool _isSearching = false;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _phoneController.removeListener(_onControllerChanged);
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  String _cleanDisplayPhoneNumber(String input) {
    if (input.isEmpty) return '';

    final sanitized = sanitizeLeadSearchQuery(input);
    final cleanDigits = sanitized.replaceAll(RegExp(r'[^\d*#]'), '');
    return cleanDigits;
  }

  Future<void> _onCopyToClipboard() async {
    if (_phoneNumber.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No number to copy'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: _phoneNumber.trim()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied ${_phoneNumber.trim()} to clipboard'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error copying to clipboard: $e');
    }
  }

  Future<void> _onPasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        final cleaned = _cleanDisplayPhoneNumber(data.text!);
        if (cleaned.isNotEmpty) {
          _phoneController.value = TextEditingValue(
            text: cleaned,
            selection: TextSelection.collapsed(offset: cleaned.length),
          );
          _updateLeadInfo();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Pasted number: $cleaned'),
                duration: const Duration(seconds: 2),
                backgroundColor: AppColors.primary,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No valid phone number found in clipboard'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No text found in clipboard'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error pasting from clipboard: $e');
    }
  }

  void _onKeyPress(String digit) {
    final text = _phoneController.text;
    final selection = _phoneController.selection;
    int start = selection.start >= 0 ? selection.start : text.length;
    int end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.replaceRange(start, end, digit);
    final newSelectionIndex = start + digit.length;

    _phoneController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
    _updateLeadInfo();
  }

  void _onBackspace() {
    final text = _phoneController.text;
    final selection = _phoneController.selection;
    int start = selection.start >= 0 ? selection.start : text.length;
    int end = selection.end >= 0 ? selection.end : text.length;

    if (start == end) {
      if (start > 0) {
        final newText = text.replaceRange(start - 1, start, '');
        _phoneController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start - 1),
        );
      }
    } else {
      final newText = text.replaceRange(start, end, '');
      _phoneController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start),
      );
    }
    _updateLeadInfo();
  }

  void _onClear() {
    _searchDebounce?.cancel();
    _phoneController.clear();
    setState(() {
      _matchedLeadId = '';
      _leadName = '--';
      _leadInitial = '';
      _leadAssignee = '--';
      _leadSource = '';
      _leadStatus = '';
      _leadStatusColor = null;
      _isMatched = false;
      _isSearching = false;
    });
  }

  void _updateLeadInfo() {
    _searchDebounce?.cancel();
    final cleanQuery = _cleanDisplayPhoneNumber(_phoneNumber);

    if (_phoneNumber != cleanQuery) {
      _phoneController.value = TextEditingValue(
        text: cleanQuery,
        selection: TextSelection.collapsed(offset: cleanQuery.length),
      );
    }

    if (cleanQuery.isEmpty) {
      setState(() {
        _matchedLeadId = '';
        _leadName = '--';
        _leadInitial = '';
        _leadAssignee = '--';
        _leadSource = '';
        _leadStatus = '';
        _leadStatusColor = null;
        _isMatched = false;
        _isSearching = false;
      });
      return;
    }

    final digitsCount = cleanQuery.replaceAll(RegExp(r'[^\d]'), '').length;
    if (digitsCount < 3) {
      setState(() {
        _matchedLeadId = '';
        _leadName = 'Enter phone number to search lead';
        _leadInitial = '';
        _leadAssignee = '--';
        _leadSource = '';
        _leadStatus = '';
        _leadStatusColor = null;
        _isMatched = false;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _leadName = 'Searching lead...';
      _leadAssignee = '--';
      _leadSource = '';
      _leadStatus = '';
      _leadStatusColor = null;
      _isMatched = false;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final repo = sl<LeadsRepository>();
        final response = await repo.searchLeadByNumber(cleanQuery);
        
        if (!mounted) return;

        response.fold(
          (failure) {
            setState(() {
              _isSearching = false;
              _leadName = 'No Matching Lead';
              _leadAssignee = '--';
              _leadSource = '';
              _leadStatus = '';
              _leadStatusColor = null;
              _isMatched = false;
            });
          },
          (result) {
            if (mounted) {
              if (result.alreadyMapped) {
                final leadNameStr = (result.name != null && result.name!.isNotEmpty)
                    ? result.name!
                    : 'Unnamed Lead';
                final initialStr = (result.initial != null && result.initial!.isNotEmpty)
                    ? result.initial!
                    : (leadNameStr.isNotEmpty ? leadNameStr[0].toUpperCase() : 'L');
                final rawAssignee = (result.assignedToName != null && result.assignedToName!.isNotEmpty)
                    ? result.assignedToName!
                    : (result.assignedToInfo != null && result.assignedToInfo!.isNotEmpty
                        ? result.assignedToInfo!
                        : 'Unassigned');
                final assigneeStr = rawAssignee.contains(' - ') ? rawAssignee.split(' - ').first.trim() : rawAssignee;

                setState(() {
                  _matchedLeadId = result.leadId ?? '';
                  _leadName = leadNameStr;
                  _leadInitial = initialStr;
                  _leadAssignee = assigneeStr;
                  _leadSource = result.sourceName ?? '';
                  _leadStatus = result.statusName ?? '';
                  _leadStatusColor = result.statusColor;
                  _isMatched = true;
                  _isSearching = false;
                });
              } else {
                setState(() {
                  _matchedLeadId = '';
                  _leadName = 'No Matching Lead';
                  _leadInitial = '';
                  _leadAssignee = '--';
                  _leadSource = '';
                  _leadStatus = '';
                  _leadStatusColor = null;
                  _isMatched = false;
                  _isSearching = false;
                });
              }
            }
          },
        );
      } catch (_) {
        if (mounted) {
          setState(() {
            _isSearching = false;
            _leadName = 'No Matching Lead';
            _leadAssignee = '--';
            _leadSource = '';
            _leadStatus = '';
            _leadStatusColor = null;
            _isMatched = false;
          });
        }
      }
    });
  }

  Future<void> _makeCall() async {
    if (_phoneNumber.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a phone number to dial'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final numberToCall = _phoneNumber.trim();
    if (_isMatched) {
      _showMatchedLeadPopup(numberToCall);
    } else {
      await DirectCallHelper.makeCall(numberToCall);
    }
  }

  void _showMatchedLeadPopup(String numberToCall) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return MappedLeadDialog(
          leadName: _leadName,
          leadInitial: _leadInitial,
          phoneNumber: numberToCall,
          sourceName: _leadSource.isNotEmpty ? _leadSource : 'Direct Lead',
          statusName: _leadStatus.isNotEmpty ? _leadStatus : 'Enrolled',
          statusColorHex: _leadStatusColor,
          assigneeName: _leadAssignee,
          onCallAnyway: () async {
            if (_matchedLeadId.isNotEmpty) {
              AutoCallRecordingUploader.makeCallAndAutoUpload(
                context: context,
                leadId: _matchedLeadId,
                phoneNumber: numberToCall,
                leadName: _leadName,
              );
            } else {
              await DirectCallHelper.makeCall(numberToCall);
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Drag Handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Top Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dialpad, color: AppColors.primary, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Dialer',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textHint, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Phone Number Input Screen Display
            GestureDetector(
              onLongPress: _onPasteFromClipboard,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderEnabled),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        focusNode: _phoneFocusNode,
                        keyboardType: TextInputType.none,
                        showCursor: true,
                        readOnly: true,
                        enableInteractiveSelection: true,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          color: AppColors.textPrimary,
                        ),
                        cursorColor: AppColors.primary,
                        cursorWidth: 2.5,
                        cursorRadius: const Radius.circular(2),
                        decoration: const InputDecoration(
                          hintText: 'Enter number...',
                          hintStyle: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.normal,
                            letterSpacing: 0,
                            color: AppColors.textHint,
                          ),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (val) {
                          _updateLeadInfo();
                        },
                      ),
                    ),
                    if (_phoneNumber.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.content_copy_rounded, color: AppColors.primary, size: 20),
                        onPressed: _onCopyToClipboard,
                        tooltip: 'Copy phone number',
                      ),
                    InkWell(
                      onTap: _onPasteFromClipboard,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.content_paste_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Tap to paste',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Lead Info Card
            GestureDetector(
              onTap: _isMatched ? () => _showMatchedLeadPopup(_phoneNumber) : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isMatched ? AppColors.primary.withOpacity(0.06) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isMatched ? AppColors.primary.withOpacity(0.3) : AppColors.borderEnabled,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isSearching) ...[
                      const Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Searching lead...',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ] else if (_isMatched) ...[
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primary.withOpacity(0.15),
                            child: Text(
                              _leadInitial.isNotEmpty
                                  ? _leadInitial
                                  : (_leadName.isNotEmpty ? _leadName[0].toUpperCase() : 'L'),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _leadName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (_leadAssignee.isNotEmpty && _leadAssignee != '--') ...[
                                  const SizedBox(height: 2),
                                  RichText(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      style: const TextStyle(fontSize: 12),
                                      children: [
                                        const TextSpan(
                                          text: 'Assigned to: ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        TextSpan(
                                          text: _leadAssignee.contains(' - ') ? _leadAssignee.split(' - ').first.trim() : _leadAssignee,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _leadSource.isNotEmpty ? _leadSource : 'Direct Lead',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ),
                                    Text(' • ', style: TextStyle(color: Colors.grey[600])),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F5E9),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _leadStatus.isNotEmpty ? _leadStatus : 'Enrolled',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _showMatchedLeadPopup(_phoneNumber),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.visibility_rounded, size: 14, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'View',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      if (_phoneNumber.length >= 3) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      size: 18,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Number not found in CRM',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () {
                                final cleanNumber = _cleanDisplayPhoneNumber(_phoneNumber);
                                final bloc = context.read<LeadsBloc>();
                                final nav = Navigator.of(context);
                                nav.pop();
                                nav.push(
                                  MaterialPageRoute(
                                    builder: (_) => BlocProvider<LeadsBloc>.value(
                                      value: bloc,
                                      child: QuickInviteScreen(
                                        initialPhoneNumber: cleanNumber,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.flash_on, size: 14, color: Colors.white),
                              label: const Text(
                                'Quick Invite',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18, color: AppColors.textHint),
                            const SizedBox(width: 8),
                            const Text(
                              'Enter phone number to search lead',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textHint,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // In-App Numeric Dialpad Circular Keys Grid
            _buildDialpadGrid(),
            const SizedBox(height: 16),

            // Action Row: Clear / Call FAB / Backspace
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox(
                  width: 56,
                  child: _phoneNumber.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_all, color: AppColors.textHint, size: 24),
                          onPressed: _onClear,
                          tooltip: 'Clear All',
                        )
                      : const SizedBox(),
                ),
                GestureDetector(
                  onTap: _makeCall,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x3322C55E),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: _phoneNumber.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.backspace_outlined, color: AppColors.textPrimary, size: 24),
                          onPressed: _onBackspace,
                          onLongPress: _onClear,
                          tooltip: 'Backspace',
                        )
                      : const SizedBox(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialpadGrid() {
    final List<Map<String, String>> keys = [
      {'number': '1', 'letters': ''},
      {'number': '2', 'letters': 'ABC'},
      {'number': '3', 'letters': 'DEF'},
      {'number': '4', 'letters': 'GHI'},
      {'number': '5', 'letters': 'JKL'},
      {'number': '6', 'letters': 'MNO'},
      {'number': '7', 'letters': 'PQRS'},
      {'number': '8', 'letters': 'TUV'},
      {'number': '9', 'letters': 'WXYZ'},
      {'number': '*', 'letters': ''},
      {'number': '0', 'letters': '+'},
      {'number': '#', 'letters': ''},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final keyData = keys[index];
        final number = keyData['number']!;
        final letters = keyData['letters']!;

        return Center(
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _onKeyPress(number);
              },
              onLongPress: number == '0'
                  ? () {
                      HapticFeedback.mediumImpact();
                      _onKeyPress('+');
                    }
                  : null,
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      number,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    if (letters.isNotEmpty)
                      Text(
                        letters,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                          letterSpacing: 0.8,
                          height: 1.0,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Redesigned Mapped Lead Dialog styled for Tickora CRM primary theme
class MappedLeadDialog extends StatelessWidget {
  final String leadName;
  final String leadInitial;
  final String phoneNumber;
  final String sourceName;
  final String statusName;
  final String? statusColorHex;
  final String assigneeName;
  final VoidCallback onCallAnyway;

  const MappedLeadDialog({
    super.key,
    required this.leadName,
    this.leadInitial = '',
    required this.phoneNumber,
    required this.sourceName,
    required this.statusName,
    this.statusColorHex,
    required this.assigneeName,
    required this.onCallAnyway,
  });

  // Color _parseColor(String? hexString, Color defaultColor) {
  //   if (hexString == null || hexString.isEmpty) return defaultColor;
  //   try {
  //     String hex = hexString.replaceAll('#', '');
  //     if (hex.length == 6) {
  //       hex = 'FF$hex';
  //     }
  //     return Color(int.parse(hex, radix: 16));
  //   } catch (_) {
  //     return defaultColor;
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final initial = leadInitial.isNotEmpty
        ? leadInitial
        : (leadName.isNotEmpty ? leadName[0].toUpperCase() : 'L');

    // final statusBgColor = statusColorHex != null
    //     ? _parseColor(statusColorHex, const Color(0xFFE8F5E9)).withOpacity(0.15)
    //     : const Color(0xFFE8F5E9);
    // final statusTextColor = statusColorHex != null
    //     ? _parseColor(statusColorHex, const Color(0xFF2E7D32))
    //     : const Color(0xFF2E7D32);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.white,
      elevation: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar in CRM Red Theme (#DB222A)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: AppColors.primary,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dial Pad',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),

          // Dialog Body
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Notice text
                const Text(
                  'This number is already mapped with a lead.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // Lead Details Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar + Name + Phone with Copy Icon
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.primary.withOpacity(0.12),
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  leadName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      phoneNumber,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: phoneNumber));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Phone number copied to clipboard'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2.0),
                                        child: Icon(
                                          Icons.copy_rounded,
                                          size: 16,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Source & Status Badge Row
                      // Row(
                      //   children: [
                      //     Flexible(
                      //       child: Text(
                      //         sourceName,
                      //         style: TextStyle(
                      //           fontSize: 13,
                      //           color: Colors.grey[600],
                      //         ),
                      //         maxLines: 1,
                      //         overflow: TextOverflow.ellipsis,
                      //       ),
                      //     ),
                      //     Padding(
                      //       padding: const EdgeInsets.symmetric(horizontal: 6),
                      //       child: Text(
                      //         '•',
                      //         style: TextStyle(color: Colors.grey[600]),
                      //       ),
                      //     ),
                      //     Container(
                      //       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      //       decoration: BoxDecoration(
                      //         color: statusBgColor,
                      //         borderRadius: BorderRadius.circular(6),
                      //       ),
                      //       child: Text(
                      //         statusName,
                      //         style: TextStyle(
                      //           color: statusTextColor,
                      //           fontSize: 11,
                      //           fontWeight: FontWeight.bold,
                      //         ),
                      //       ),
                      //     ),
                      //   ],
                      // ),
                      // const SizedBox(height: 8),

                      // Assigned To Line
                      if (assigneeName.isNotEmpty && assigneeName != '--')
                        RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(fontSize: 13),
                            children: [
                              const TextSpan(
                                text: 'Assigned to: ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: assigneeName.contains(' - ') ? assigneeName.split(' - ').first.trim() : assigneeName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Buttons: Cancel (Outlined) & Call Anyway (Filled)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onCallAnyway();
                        },
                        child: const Text(
                          'Call Anyway',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
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
