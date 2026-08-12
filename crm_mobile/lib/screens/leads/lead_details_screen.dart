import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/spinning_logo.dart';
import '../../injection/injection.dart';
import '../../features/leads/presentation/bloc/leads_bloc.dart';
import '../../features/leads/presentation/bloc/leads_event.dart';
import '../../features/leads/presentation/bloc/leads_state.dart';
import 'package:file_picker/file_picker.dart';
import '../../features/leads/domain/entities/lead_detail.dart';
import '../../features/leads/domain/entities/attachment.dart';

class LeadDetailsScreen extends StatelessWidget {
  final String leadId;
  const LeadDetailsScreen({super.key, required this.leadId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LeadsBloc>()..add(FetchLeadDetails(leadId)),
      child: const LeadDetailsView(),
    );
  }
}

class LeadDetailsView extends StatefulWidget {
  const LeadDetailsView({super.key});

  @override
  State<LeadDetailsView> createState() => _LeadDetailsViewState();
}

class _LeadDetailsViewState extends State<LeadDetailsView> {
  int _activeTabIndex = 0;
  final List<String> _tabs = ['Overview', 'Activities','Documents'];

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) {
      buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    }
    return Colors.grey;
  }

  String _formatCurrency(double? value) {
    if (value == null || value == 0.0) return '\$0.00';
    final formatter = NumberFormat.simpleCurrency(decimalDigits: 0);
    return formatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
      ),
      body: BlocBuilder<LeadsBloc, LeadsState>(
        builder: (context, state) {
          if (state is LeadDetailsLoading) {
            return const Center(child: SpinningLogo(size: 60));
          } else if (state is LeadDetailsError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(state.message, style: const TextStyle(color: AppColors.primary)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      // Trigger retry
                      Navigator.pop(context);
                    },
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          } else if (state is LeadDetailsLoaded) {
            final lead = state.leadDetail;
            final fullName = '${lead.firstName} ${lead.lastName}';
            
            final statusColor = lead.status?.color != null 
                ? _hexToColor(lead.status!.color) 
                : AppColors.primary;

            final initials = (lead.firstName.isNotEmpty ? lead.firstName[0] : '') +
                             (lead.lastName.isNotEmpty ? lead.lastName[0] : '');

            return SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Section
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: statusColor,
                          child: Text(
                            initials.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          fullName,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        if (lead.industry != null && lead.industry!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            lead.industry!,
                            style: const TextStyle(fontSize: 14, color: AppColors.textHint),
                          ),
                        ],
                        if (lead.companyName.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            lead.companyName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Metrics Cards Row (Stage, Value, Score)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            'STATUS',
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  lead.status?.statusName ?? '-',
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricCard(
                            'VALUE',
                            Text(
                              _formatCurrency(lead.annualRevenue),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricCard(
                            'SCORE',
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.trip_origin, size: 14, color: (lead.score ?? 0) > 50 ? Colors.green : Colors.red),
                                const SizedBox(width: 4),
                                Text(
                                  '${lead.score ?? 0}%',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tab Bar Headers
                  _buildTabBar(state),

                  // Active Tab Content
                  Expanded(
                    child: IndexedStack(
                      index: _activeTabIndex,
                      children: [
                        _buildOverviewTab(lead),
                        _buildActivitiesTab(state),
                        _buildDocumentsTab(state),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return const SizedBox();
        },
      ),
    );
  }

  Widget _buildMetricCard(String title, Widget valueWidget) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textHint, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          valueWidget,
        ],
      ),
    );
  }

  Widget _buildTabBar(LeadDetailsLoaded state) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderEnabled)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_tabs.length, (index) {
          final isSelected = index == _activeTabIndex;
          return GestureDetector(
            onTap: () {
              setState(() => _activeTabIndex = index);
              if (index == 1 && state.auditLogs == null) {
                context.read<LeadsBloc>().add(FetchLeadAuditLogs(state.leadDetail.id));
              } else if (index == 3 && state.attachments == null) {
                context.read<LeadsBloc>().add(FetchLeadAttachments(state.leadDetail.id));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    width: 2.0,
                  ),
                ),
              ),
              child: Text(
                _tabs[index],
                style: TextStyle(
                  color: isSelected ? AppColors.primary : AppColors.textHint,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOverviewTab(LeadDetail lead) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Contact Info Card
          _buildInfoCard(
            'Contact Information',
            [
              _buildInfoRow(Icons.mail_outline, 'Email', lead.email),
              _buildInfoRow(Icons.phone_outlined, 'Phone', lead.phone),
              if (lead.alternatePhone != null && lead.alternatePhone!.isNotEmpty)
                _buildInfoRow(Icons.phone_iphone_outlined, 'Alternate Phone', lead.alternatePhone!),
              if (lead.website != null && lead.website!.isNotEmpty)
                _buildInfoRow(Icons.language_outlined, 'Website', lead.website!),
            ],
          ),
          const SizedBox(height: 16),

          // Address Info Card
          _buildInfoCard(
            'Address Information',
            [
              _buildInfoRow(
                Icons.map_outlined,
                'Address',
                lead.address ?? '',
                subvalue: '${lead.city ?? ''}${lead.city != null && lead.state != null ? ", " : ""}${lead.state ?? ''} ${lead.postalCode ?? ''}\n${lead.country ?? ''}',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Additional Details Card
          _buildInfoCard(
            'Additional Information',
            [
              _buildInfoRow(Icons.person_outline, 'Owner', lead.ownerUserName ?? 'Unassigned'),
              if (lead.priority != null)
                _buildInfoRow(Icons.flag_outlined, 'Priority', lead.priority!),
              if (lead.source?.name != null)
                _buildInfoRow(Icons.share_outlined, 'Source', lead.source!.name),
              if (lead.createdAt != null)
                _buildInfoRow(Icons.calendar_today_outlined, 'Created At', DateFormat('MMM dd, yyyy').format(lead.createdAt!)),
              if (lead.description != null && lead.description!.isNotEmpty)
                _buildInfoRow(Icons.description_outlined, 'Description', lead.description!),
            ],
          ),

          if (lead.customFields.where((field) => field.fieldType != 'ATTACHMENT').isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoCard(
              'Custom Fields',
              lead.customFields
                  .where((field) => field.fieldType != 'ATTACHMENT')
                  .map((field) {
                return _buildInfoRow(Icons.toc_outlined, field.label, field.value?.toString() ?? '');
              }).toList(),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab(String tabName) {
    return Center(
      child: Text(
        '$tabName coming soon',
        style: const TextStyle(color: AppColors.textHint, fontSize: 14),
      ),
    );
  }

  Widget _buildDocumentsTab(LeadDetailsLoaded state) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // List body
          Expanded(
            child: _buildAttachmentsBody(state),
          ),
          
          const SizedBox(height: 12),
          
          // Upload Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              icon: state.isAttachmentsLoading 
                  ? const SizedBox(
                      width: 18, 
                      height: 18, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(
                state.isAttachmentsLoading ? 'Uploading...' : 'Upload Document',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: state.isAttachmentsLoading 
                  ? null 
                  : () => _pickAndUploadFile(context, state.leadDetail.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsBody(LeadDetailsLoaded state) {
    if (state.isAttachmentsLoading && state.attachments == null) {
      return const Center(child: SpinningLogo(size: 40));
    }
    if (state.attachmentsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                state.attachmentsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.primary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadAttachments(state.leadDetail.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final attachments = state.attachments ?? [];
    if (attachments.isEmpty) {
      return const Center(
        child: Text(
          'No documents uploaded yet.',
          style: TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      itemCount: attachments.length,
      itemBuilder: (context, index) {
        final doc = attachments[index];
        
        // Define file type icon
        IconData fileIcon = Icons.insert_drive_file_outlined;
        Color fileColor = Colors.grey;

        final lowerType = doc.fileType.toLowerCase();
        final lowerName = doc.fileName.toLowerCase();
        
        if (lowerType.contains('image') || lowerName.endsWith('.png') || lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
          fileIcon = Icons.image_outlined;
          fileColor = Colors.blue;
        } else if (lowerType.contains('pdf') || lowerName.endsWith('.pdf')) {
          fileIcon = Icons.picture_as_pdf_outlined;
          fileColor = Colors.red;
        } else if (lowerType.contains('word') || lowerName.endsWith('.doc') || lowerName.endsWith('.docx')) {
          fileIcon = Icons.description_outlined;
          fileColor = Colors.indigo;
        } else if (lowerType.contains('excel') || lowerName.endsWith('.xls') || lowerName.endsWith('.xlsx') || lowerName.endsWith('.csv')) {
          fileIcon = Icons.table_chart_outlined;
          fileColor = Colors.green;
        }

        final dateStr = doc.createdAt != null 
            ? DateFormat('MMM dd, yyyy').format(doc.createdAt!) 
            : 'Unknown Date';

        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.borderEnabled),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: fileColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(fileIcon, color: fileColor, size: 24),
                ),
                const SizedBox(width: 16),
                
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.fileName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Uploaded on $dateStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Trailing Action Button
                IconButton(
                  icon: const Icon(Icons.file_open_outlined, color: AppColors.textHint, size: 20),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Opening ${doc.fileName}...')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _pickAndUploadFile(BuildContext context, String leadId) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        if (context.mounted) {
          context.read<LeadsBloc>().add(UploadLeadAttachment(
            leadId: leadId,
            filePath: filePath,
          ));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
  }

  Widget _buildActivitiesTab(LeadDetailsLoaded state) {
    if (state.isAuditLogsLoading) {
      return const Center(child: SpinningLogo(size: 40));
    }
    if (state.auditLogsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                state.auditLogsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.primary, fontSize: 14),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadAuditLogs(state.leadDetail.id));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final logs = state.auditLogs?.content ?? [];
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'No activities recorded yet.',
          style: TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        
        // Define action icons and colors
        IconData actionIcon = Icons.info_outline;
        Color actionColor = Colors.blue;
        
        if (log.actionType == 'CREATE') {
          actionIcon = Icons.add_circle_outline;
          actionColor = Colors.green;
        } else if (log.actionType == 'UPDATE') {
          actionIcon = Icons.edit_outlined;
          actionColor = Colors.orange;
        } else if (log.actionType == 'DELETE') {
          actionIcon = Icons.delete_outline;
          actionColor = Colors.red;
        }

        final timeStr = log.actionAt != null 
            ? DateFormat('MMM dd, yyyy  •  h:mm a').format(log.actionAt!) 
            : 'Just now';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline line & icon
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: actionColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(actionIcon, color: actionColor, size: 18),
                ),
                if (index < logs.length - 1)
                  Container(
                    width: 2,
                    height: 50,
                    color: AppColors.borderEnabled,
                  ),
              ],
            ),
            const SizedBox(width: 16),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.message,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'By ${log.actionByName.trim()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.textHint, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard(String title, List<Widget> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderEnabled),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) => rows[index],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {String? subvalue}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textHint, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
              const SizedBox(height: 2),
              Text(
                value.isNotEmpty ? value : '-',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              ),
              if (subvalue != null && subvalue.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subvalue,
                  style: const TextStyle(fontSize: 13, color: AppColors.textHint),
                ),
              ]
            ],
          ),
        ),
      ],
    );
  }
}
