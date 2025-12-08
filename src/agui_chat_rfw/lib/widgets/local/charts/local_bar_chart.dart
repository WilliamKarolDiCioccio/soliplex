import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart';

import '../../../core/utils/security_validator.dart';

/// LocalBarChart - RFW wrapper for fl_chart BarChart.
///
/// Maps RFW data format to BarChartGroupData for bar chart rendering.
///
/// Expected data format:
/// ```
/// {
///   bars: [
///     {label: "Jan", value: 100, color: 0xFF2196F3},
///     {label: "Feb", value: 150},
///     ...
///   ],
///   defaultColor: 0xFF2196F3,   // optional, default bar color
///   barWidth: 20,               // optional, bar width
///   showValues: true,           // optional, show values on bars
///   showGrid: true,             // optional, show grid lines
///   title: "Monthly Sales",     // optional, chart title
///   maxY: 200,                  // optional, max Y axis value
///   grouped: false,             // optional, grouped bars mode
/// }
/// ```
Widget buildLocalBarChart(BuildContext context, DataSource source) {
  // Extract bar data
  final barCount = source.length(<Object>['bars']);
  final barGroups = <BarChartGroupData>[];
  final labels = <String>[];

  final defaultColorValue = source.v<int>(<Object>['defaultColor']);
  final defaultColor = defaultColorValue != null ? Color(defaultColorValue) : Colors.blue;

  final barWidth = source.v<double>(<Object>['barWidth']) ?? 20.0;
  final showValues = source.v<bool>(<Object>['showValues']) ?? true;
  final showGrid = source.v<bool>(<Object>['showGrid']) ?? true;
  final maxY = source.v<double>(<Object>['maxY']);
  final title = source.v<String>(<Object>['title']);

  for (var i = 0; i < barCount; i++) {
    final label = source.v<String>(<Object>['bars', i, 'label']) ?? '';
    final value = source.v<double>(<Object>['bars', i, 'value']);
    final colorValue = source.v<int>(<Object>['bars', i, 'color']);

    labels.add(label);

    if (value != null && SecurityValidator.isValidChartValue(value)) {
      final barColor = colorValue != null ? Color(colorValue) : defaultColor;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              color: barColor,
              width: barWidth,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
          showingTooltipIndicators: showValues ? [0] : [],
        ),
      );
    }
  }

  if (barGroups.isEmpty) {
    return const Center(
      child: Text('No valid bar data', style: TextStyle(color: Colors.grey)),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      SizedBox(
        height: 200,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            gridData: FlGridData(show: showGrid),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index >= 0 && index < labels.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          labels[index],
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: Colors.grey.shade300),
            ),
            barGroups: barGroups,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final label = groupIndex < labels.length ? labels[groupIndex] : '';
                  return BarTooltipItem(
                    '$label\n${rod.toY.toStringAsFixed(1)}',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
