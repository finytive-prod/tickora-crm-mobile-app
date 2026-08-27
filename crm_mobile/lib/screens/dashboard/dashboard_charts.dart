import 'dart:math';
import 'package:flutter/material.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/models/dashboard_models.dart';

// ─── 1. CUSTOM LINE CHART (LEAD TREND ANALYSIS) ────────────────────────────

class TrendLineChart extends StatelessWidget {
  final String activePeriod; 
  final LeadTrendData? trendData;

  const TrendLineChart({
    super.key,
    required this.activePeriod,
    this.trendData,
  });

  @override
  Widget build(BuildContext context) {
    final createdList = trendData?.leadsCreated ?? [];
    final wonList = trendData?.leadsWon ?? [];

    if (createdList.isEmpty && wonList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.show_chart_outlined, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                'No lead trend data available for ${activePeriod.toUpperCase()}',
                style: const TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final Set<String> uniqueDates = {};
    for (var item in createdList) {
      if (item.date.trim().isNotEmpty) uniqueDates.add(item.date);
    }
    for (var item in wonList) {
      if (item.date.trim().isNotEmpty) uniqueDates.add(item.date);
    }

    final List<double> series1 = [];
    final List<double> series2 = [];
    final List<String> labels = [];

    if (uniqueDates.isNotEmpty) {
      final sortedDates = uniqueDates.toList()..sort();

      final Set<String> datesWithNonZeroData = {};
      for (final date in sortedDates) {
        final cCount = createdList.where((e) => e.date == date).fold<int>(0, (sum, e) => sum + e.count);
        final wCount = wonList.where((e) => e.date == date).fold<int>(0, (sum, e) => sum + e.count);
        if (cCount > 0 || wCount > 0) {
          datesWithNonZeroData.add(date);
        }
      }

      final int total = sortedDates.length;

      for (int idx = 0; idx < total; idx++) {
        final date = sortedDates[idx];
        final cCount = createdList.where((e) => e.date == date).fold<int>(0, (sum, e) => sum + e.count);
        final wCount = wonList.where((e) => e.date == date).fold<int>(0, (sum, e) => sum + e.count);

        series1.add(cCount.toDouble());
        series2.add(wCount.toDouble());

        String rawDate = date;
        if (rawDate.contains('-')) {
          final parts = rawDate.split('-');
          if (parts.length >= 3) {
            rawDate = '${parts[1]}/${parts[2]}';
          }
        }

        labels.add(rawDate.isEmpty ? '?' : rawDate);
      }
    } else {
      final maxLen = max(createdList.length, wonList.length);
      for (int i = 0; i < maxLen; i++) {
        final createdItem = i < createdList.length ? createdList[i] : null;
        final wonItem = i < wonList.length ? wonList[i] : null;

        series1.add(createdItem?.count.toDouble() ?? 0.0);
        series2.add(wonItem?.count.toDouble() ?? 0.0);
        labels.add('P${i + 1}');
      }
    }

    final int totalPoints = series1.length;
    final bool isScrollable = totalPoints > 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isScrollable)
          const Padding(
            padding: EdgeInsets.only(bottom: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.swipe_left_rounded, size: 14, color: AppColors.textHint),
                SizedBox(width: 4),
                Text(
                  'Swipe to view full month',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 220,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double canvasWidth = isScrollable ? max(constraints.maxWidth, totalPoints * 44.0) : constraints.maxWidth;

              final chartWidget = SizedBox(
                width: canvasWidth,
                height: 220,
                child: CustomPaint(
                  size: Size(canvasWidth, 220),
                  painter: _LineChartPainter(
                    series1: series1,
                    series2: series2,
                    labels: labels,
                    line1Color: const Color(0xFFDB222A),
                    line2Color: const Color(0xFF059669),
                  ),
                ),
              );

              if (isScrollable) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: chartWidget,
                );
              }
              return chartWidget;
            },
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem('Leads Created', const Color(0xFFDB222A)),
            const SizedBox(width: 24),
            _buildLegendItem('Leads Won', const Color(0xFF059669)),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> series1;
  final List<double> series2;
  final List<String> labels;
  final Color line1Color;
  final Color line2Color;

  _LineChartPainter({
    required this.series1,
    required this.series2,
    required this.labels,
    required this.line1Color,
    required this.line2Color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFF3F4F6)
      ..strokeWidth = 1.0;

    final textStyle = const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.w500);
    final valStyle1 = TextStyle(color: line1Color, fontSize: 10, fontWeight: FontWeight.bold);
    final valStyle2 = TextStyle(color: line2Color, fontSize: 10, fontWeight: FontWeight.bold);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    const double leftPadding = 28;
    const double rightPadding = 12;
    const double topPadding = 24;
    const double bottomPadding = 24;
    final double chartWidth = size.width - leftPadding - rightPadding;
    final double chartHeight = size.height - topPadding - bottomPadding;

    final maxS1 = series1.isNotEmpty ? series1.reduce(max) : 5.0;
    final maxS2 = series2.isNotEmpty ? series2.reduce(max) : 5.0;
    final double maxVal = max(maxS1, maxS2).clamp(5.0, 100000.0);

    const int ySteps = 4;
    for (int i = 0; i <= ySteps; i++) {
      final yRatio = i / ySteps;
      final y = topPadding + chartHeight * (1 - yRatio);

      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );

      final val = (maxVal * yRatio).toInt();
      textPainter.text = TextSpan(text: '$val', style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y - 6));
    }

    if (series1.isEmpty) return;
    final double xStep = series1.length > 1 ? chartWidth / (series1.length - 1) : chartWidth;

    for (int i = 0; i < labels.length; i++) {
      if (labels[i].isEmpty) continue;
      final x = leftPadding + (i * xStep);
      textPainter.text = TextSpan(text: labels[i], style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height - bottomPadding + 6));
    }

    void drawSeries(List<double> data, Color color, TextStyle valStyle, bool drawValueTop) {
      if (data.isEmpty) return;
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final haloPaint = Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;

      final dotInnerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      final path = Path();
      final areaPath = Path();
      final points = <Offset>[];

      for (int i = 0; i < data.length; i++) {
        final x = leftPadding + (i * xStep);
        final y = topPadding + chartHeight * (1 - (data[i] / maxVal));
        points.add(Offset(x, y));

        if (i == 0) {
          path.moveTo(x, y);
          areaPath.moveTo(x, topPadding + chartHeight);
          areaPath.lineTo(x, y);
        } else {
          final prevPoint = points[i - 1];
          final controlPoint1 = Offset(prevPoint.dx + (xStep / 2), prevPoint.dy);
          final controlPoint2 = Offset(x - (xStep / 2), y);
          path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, x, y);
          areaPath.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, x, y);
        }

        if (i == data.length - 1) {
          areaPath.lineTo(x, topPadding + chartHeight);
          areaPath.close();
        }
      }

      final areaGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.0),
        ],
      );

      final areaPaint = Paint()
        ..shader = areaGradient.createShader(Rect.fromLTWH(leftPadding, topPadding, chartWidth, chartHeight))
        ..style = PaintingStyle.fill;

      canvas.drawPath(areaPath, areaPaint);
      canvas.drawPath(path, linePaint);

      for (int i = 0; i < points.length; i++) {
        final pt = points[i];
        final val = data[i].toInt();

        if (val > 0) {
          canvas.drawCircle(pt, 5, haloPaint);
          canvas.drawCircle(pt, 3, dotPaint);
          canvas.drawCircle(pt, 1.2, dotInnerPaint);

          textPainter.text = TextSpan(text: '$val', style: valStyle);
          textPainter.layout();
          final yOffset = drawValueTop ? pt.dy - 16 : pt.dy + 6;
          textPainter.paint(canvas, Offset(pt.dx - (textPainter.width / 2), yOffset));
        } else {
          canvas.drawCircle(pt, 1.5, dotPaint);
        }
      }
    }

    drawSeries(series1, line1Color, valStyle1, true);
    drawSeries(series2, line2Color, valStyle2, false);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

// ─── 2. SALES PIPELINE HORIZONTAL BAR CHART ─────────────────────────────────

class PipelineBarChart extends StatelessWidget {
  final List<SalesPipelineItem> items;

  const PipelineBarChart({super.key, this.items = const []});

  static const List<Color> _palette = [
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFFFF6600),
    Color(0xFFFB923C),
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
  ];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.filter_alt_outlined, size: 44, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              const Text(
                'No sales pipeline data available',
                style: TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final double maxValue = items.map((e) => e.value).fold(1.0, (prev, curr) => max(prev, curr));

    return Column(
      children: items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final color = _palette[idx % _palette.length];
        final ratio = maxValue > 0 ? item.value / maxValue : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  item.stageName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio.clamp(0.05, 1.0),
                      child: Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.value.toInt()}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── 3. DONUT CHART (LEAD STATUS & SOURCE DISTRIBUTION) ─────────────────────

class DonutSegment {
  final String label;
  final double value;
  final Color color;

  DonutSegment({required this.label, required this.value, required this.color});
}

class DonutChartWidget extends StatelessWidget {
  final String title;
  final List<DonutSegment> segments;

  const DonutChartWidget({
    super.key,
    required this.title,
    required this.segments,
  });

  @override
  Widget build(BuildContext context) {
    final double total = segments.fold(0, (sum, item) => sum + item.value);

    if (total == 0 || segments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.pie_chart_outline, size: 44, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                'No $title data available',
                style: const TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _DonutPainter(segments: segments, total: total),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: segments.map((seg) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: seg.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${seg.label} (${seg.value.toInt()})',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final double total;

  _DonutPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    const strokeWidth = 24.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (total == 0 || segments.isEmpty) {
      paint.color = const Color(0xFFE5E7EB);
      canvas.drawCircle(center, radius - (strokeWidth / 2), paint);
      return;
    }

    double startAngle = -pi / 2;
    const gapAngle = 0.04;

    for (final seg in segments) {
      final sweepAngle = (seg.value / total) * 2 * pi - gapAngle;
      if (sweepAngle > 0) {
        paint.color = seg.color;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2)),
          startAngle,
          sweepAngle,
          false,
          paint,
        );
      }
      startAngle += sweepAngle + gapAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

// ─── 4. MONTHLY REVENUE TARGET CARD ─────────────────────────────────────────

class MonthlyRevenueTargetCard extends StatelessWidget {
  final RevenueTargetData targetData;

  const MonthlyRevenueTargetCard({
    super.key,
    required this.targetData,
  });

  @override
  Widget build(BuildContext context) {
    final target = targetData.target;
    final achieved = targetData.achieved;
    final progressPct = targetData.progressPercentage.isNaN
        ? (target > 0 ? (achieved / target * 100) : 0.0)
        : targetData.progressPercentage;

    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      value: target > 0 ? (achieved / target).clamp(0.0, 1.0) : 0.0,
                      strokeWidth: 8,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  Text(
                    '${progressPct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderEnabled),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTargetStat('TARGET', '₹${target.toInt()}'),
              _buildTargetStat('ACHIEVED', '₹${achieved.toInt()}'),
              _buildTargetStat('PROGRESS', '${progressPct.toStringAsFixed(1)}%', isPrimary: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTargetStat(String label, String value, {bool isPrimary = false}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textHint, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isPrimary ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
