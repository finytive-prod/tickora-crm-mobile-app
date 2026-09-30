import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';
import 'package:crm_mobile/models/attachment.dart';
import 'package:crm_mobile/blocs/leads_bloc.dart';
import 'package:crm_mobile/blocs/leads_event.dart';
import 'package:crm_mobile/blocs/leads_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/network/api_client.dart';
import 'package:crm_mobile/core/network/api_constants.dart';

class LeadDocumentsTab extends StatelessWidget {
  final LeadDetailsLoaded state;

  const LeadDocumentsTab({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Documents & Attachments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.primary),
                tooltip: 'Refresh Documents',
                onPressed: () {
                  context.read<LeadsBloc>().add(FetchLeadAttachments(state.leadDetail.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refreshing documents...'),
                      duration: Duration(seconds: 1),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildAttachmentsBody(context),
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

  Widget _buildAttachmentsBody(BuildContext context) {
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
    final serverAttachments = state.attachments ?? [];
    final List<Attachment> allDocuments = List.from(serverAttachments);
    final seenDocIds = serverAttachments.map((a) => a.id).toSet();
    final seenDocNames = serverAttachments.map((a) => a.fileName.toLowerCase()).toSet();

    for (final cf in state.leadDetail.customFields) {
      final valStr = cf.value?.toString().trim() ?? '';
      if (valStr.isEmpty) continue;
      final typeUpper = cf.fieldType.toUpperCase();
      final lowerVal = valStr.toLowerCase();
      final isFileField = typeUpper == 'FILE' ||
          typeUpper == 'ATTACHMENT' ||
          typeUpper == 'DOCUMENT' ||
          typeUpper == 'IMAGE' ||
          lowerVal.endsWith('.pdf') ||
          lowerVal.endsWith('.doc') ||
          lowerVal.endsWith('.docx') ||
          lowerVal.endsWith('.xls') ||
          lowerVal.endsWith('.xlsx') ||
          lowerVal.endsWith('.png') ||
          lowerVal.endsWith('.jpg') ||
          lowerVal.endsWith('.jpeg') ||
          lowerVal.endsWith('.csv') ||
          lowerVal.endsWith('.txt') ||
          lowerVal.endsWith('.zip');

      if (isFileField && !seenDocNames.contains(lowerVal)) {
        seenDocNames.add(lowerVal);
        final docId = 'cf_${cf.fieldId}';
        if (!seenDocIds.contains(docId)) {
          seenDocIds.add(docId);
          allDocuments.add(Attachment(
            id: docId,
            leadId: state.leadDetail.id,
            fileName: '${cf.label}: $valStr',
            fileType: cf.fieldType,
            filePath: valStr,
            createdAt: state.leadDetail.createdAt,
          ));
        }
      }
    }

    if (allDocuments.isEmpty) {
      return const Center(
        child: Text(
          'No documents uploaded yet.',
          style: TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: allDocuments.length,
      itemBuilder: (context, index) {
        final doc = allDocuments[index];
        
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
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _downloadAttachment(context, doc),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: fileColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(fileIcon, color: fileColor, size: 24),
                  ),
                  const SizedBox(width: 16),
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
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: AppColors.primary, size: 22),
                    tooltip: 'Download',
                    onPressed: () => _downloadAttachment(context, doc),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _downloadAttachment(BuildContext context, Attachment doc) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SpinningLogo(size: 44),
              const SizedBox(height: 16),
              Text(
                'Downloading ${doc.fileName}...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Please wait, saving to Downloads folder.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final displayFileName = doc.fileName.isNotEmpty ? doc.fileName : 'attachment_${doc.id}';
      final sanitizedName = displayFileName.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final tempFile = File('${tempDir.path}/$sanitizedName');

      final leadsBaseUrl = ApiUrl.leadService;
      String downloadUrl = '$leadsBaseUrl/leads/attachments/${doc.id}/download';
      if (doc.id.startsWith('cf_')) {
        downloadUrl = '$leadsBaseUrl/leads/attachments/${doc.fileName}/download';
      }
      try {
        await sl<ApiClient>().download(
          downloadUrl,
          tempFile.path,
        );
      } catch (_) {
        final fallbackUrl = '$leadsBaseUrl/leads/${doc.leadId}/attachments/${doc.fileName}/download';
        await sl<ApiClient>().download(
          fallbackUrl,
          tempFile.path,
        );
      }

      if (await tempFile.exists() && (await tempFile.length()) > 0) {
        String? finalPath;
        if (Platform.isAndroid) {
          try {
            finalPath = await const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod<String>(
              'saveToDownloads',
              {
                'filePath': tempFile.path,
                'fileName': sanitizedName,
                'mimeType': doc.fileType,
              },
            );
          } catch (e) {
            debugPrint('Error invoking saveToDownloads: $e');
          }
        }

        // Close download loader dialog
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

        final savedFile = (finalPath != null && !finalPath.startsWith('content://')) ? File(finalPath) : tempFile;

        if (context.mounted) {
          final String shortName = doc.fileName.length > 25 
              ? '${doc.fileName.substring(0, 12)}...${doc.fileName.substring(doc.fileName.length - 10)}' 
              : doc.fileName;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Download Complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: Text('Successfully saved "$shortName" to your Downloads folder.', style: const TextStyle(fontSize: 14)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.textHint)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      if (Platform.isAndroid) {
                        await const MethodChannel('com.example.crm_mobile/call_recording').invokeMethod(
                          'openFile',
                          {
                            'filePath': savedFile.path,
                            'mimeType': doc.fileType,
                          },
                        );
                      } else {
                        final Uri uri = Uri.file(savedFile.path);
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      debugPrint('Could not launch file: $e');
                    }
                  },
                  child: const Text('OPEN FILE'),
                ),
              ],
            ),
          );
        }
      } else {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        if (context.mounted) {
          final String shortName = doc.fileName.length > 25 
              ? '${doc.fileName.substring(0, 12)}...${doc.fileName.substring(doc.fileName.length - 10)}' 
              : doc.fileName;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Download Failed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              content: Text('Could not download "$shortName". Please check your connection and try again.', style: const TextStyle(fontSize: 14)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.textHint)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint('Download error: $e');
      if (context.mounted) {
        final String shortName = doc.fileName.length > 25 
            ? '${doc.fileName.substring(0, 12)}...${doc.fileName.substring(doc.fileName.length - 10)}' 
            : doc.fileName;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Download Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: Text('An error occurred while downloading "$shortName".', style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL', style: TextStyle(color: AppColors.textHint)),
              ),
            ],
          ),
        );
      }
    }
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
}
