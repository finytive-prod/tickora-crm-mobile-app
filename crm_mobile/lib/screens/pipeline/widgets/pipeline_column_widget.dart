import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/pipeline_model.dart';
import 'package:crm_mobile/screens/pipeline/widgets/pipeline_lead_card.dart';

class PipelineColumnWidget extends StatefulWidget {
  final PipelineColumnData columnData;
  final Function(PipelineLeadItem lead, PipelineStatus targetStatus) onLeadDropped;
  final Function(Offset globalPosition)? onDragUpdate;
  final VoidCallback? onDragEnd;
  final Function(PipelineLeadItem lead, PipelineStatus currentStatus)? onStatusTap;

  const PipelineColumnWidget({
    super.key,
    required this.columnData,
    required this.onLeadDropped,
    this.onDragUpdate,
    this.onDragEnd,
    this.onStatusTap,
  });

  @override
  State<PipelineColumnWidget> createState() => _PipelineColumnWidgetState();
}

class _PipelineColumnWidgetState extends State<PipelineColumnWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final status = widget.columnData.status;
    final leads = widget.columnData.leads;
    final totalCount = widget.columnData.totalElements;

    return Container(
      width: 290,
      margin: const EdgeInsets.only(right: 14.0),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isHovered ? status.color : const Color(0xFFE5E7EB),
          width: _isHovered ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: status.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.statusName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$totalCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Drag Target Body
          Expanded(
            child: DragTarget<PipelineLeadItem>(
              onWillAcceptWithDetails: (details) {
                setState(() => _isHovered = true);
                return true;
              },
              onLeave: (_) {
                setState(() => _isHovered = false);
              },
              onAcceptWithDetails: (details) {
                setState(() => _isHovered = false);
                widget.onLeadDropped(details.data, status);
              },
              builder: (context, candidateData, rejectedData) {
                if (leads.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.layers_clear_outlined,
                            size: 40,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No Leads',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(10.0),
                  itemCount: leads.length,
                  itemBuilder: (context, index) {
                    final lead = leads[index];

                    return LongPressDraggable<PipelineLeadItem>(
                      data: lead,
                      delay: const Duration(milliseconds: 100),
                      onDragUpdate: (details) => widget.onDragUpdate?.call(details.globalPosition),
                      onDragEnd: (_) => widget.onDragEnd?.call(),
                      onDraggableCanceled: (_, __) => widget.onDragEnd?.call(),
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      feedback: Material(
                        color: Colors.transparent,
                        elevation: 10,
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 270,
                          child: PipelineLeadCard(
                            lead: lead,
                            status: status,
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.25,
                        child: PipelineLeadCard(
                          lead: lead,
                          status: status,
                        ),
                      ),
                      child: PipelineLeadCard(
                        lead: lead,
                        status: status,
                        onStatusTap: () => widget.onStatusTap?.call(lead, status),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
