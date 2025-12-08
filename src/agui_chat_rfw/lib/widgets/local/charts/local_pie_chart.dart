import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart';

import '../../../core/utils/security_validator.dart';

/// LocalPieChart - RFW wrapper for fl_chart PieChart.
///
/// Maps RFW data format to PieChartSectionData for pie/donut chart rendering.
///
/// Expected data format:
/// ```
/// {
///   segments: [
///     {value: 30, color: 0xFF2196F3, title: "Sales"},
///     {value: 20, color: 0xFF4CAF50, title: "Marketing"},
///     ...
///   ],
///   showLabels: true,           // optional, show segment labels
///   showPercentage: true,       // optional, show percentage values
///   centerRadius: 0,            // optional, 0 for pie, >0 for donut
///   sectionRadius: 100,         // optional, outer radius
///   title: "Revenue Split",     // optional, chart title
///   centerText: "Total",        // optional, text in center (donut mode)
/// }
/// ```
Widget buildLocalPieChart(BuildContext context, DataSource source) {
  // Extract segment data
  final segmentCount = source.length(<Object>['segments']);
  final sections = <PieChartSectionData>[];

  // Default colors for segments without specified color
  final defaultColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.amber,
    Colors.indigo,
  ];

  final showLabels = source.v<bool>(<Object>['showLabels']) ?? true;
  final showPercentage = source.v<bool>(<Object>['showPercentage']) ?? true;
  final centerRadius = source.v<double>(<Object>['centerRadius']) ?? 0.0;
  final sectionRadius = source.v<double>(<Object>['sectionRadius']) ?? 100.0;
  final title = source.v<String>(<Object>['title']);
  final centerText = source.v<String>(<Object>['centerText']);

  // Calculate total for percentage
  double total = 0;
  final rawValues = <double>[];
  for (var i = 0; i < segmentCount; i++) {
    final value = source.v<double>(<Object>['segments', i, 'value']);
    if (value != null && SecurityValidator.isValidChartValue(value) && value > 0) {
      rawValues.add(value);
      total += value;
    } else {
      rawValues.add(0);
    }
  }

  if (total == 0) {
    return const Center(
      child: Text('No valid segment data', style: TextStyle(color: Colors.grey)),
    );
  }

  for (var i = 0; i < segmentCount; i++) {
    final value = rawValues[i];
    if (value <= 0) continue;

    final segmentTitle = source.v<String>(<Object>['segments', i, 'title']) ?? '';
    final colorValue = source.v<int>(<Object>['segments', i, 'color']);
    final color = colorValue != null ? Color(colorValue) : defaultColors[i % defaultColors.length];

    final percentage = (value / total * 100);
    String displayTitle = '';
    if (showLabels && segmentTitle.isNotEmpty) {
      displayTitle = segmentTitle;
    }
    if (showPercentage) {
      displayTitle += displayTitle.isNotEmpty ? '\n' : '';
      displayTitle += '${percentage.toStringAsFixed(1)}%';
    }

    sections.add(
      PieChartSectionData(
        value: value,
        color: color,
        title: displayTitle,
        radius: sectionRadius,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titlePositionPercentageOffset: 0.55,
      ),
    );
  }

  if (sections.isEmpty) {
    return const Center(
      child: Text('No valid segment data', style: TextStyle(color: Colors.grey)),
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
        height: 250,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: centerRadius,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    // Touch handling can be extended via onEvent
                  },
                ),
              ),
            ),
            if (centerText != null && centerRadius > 0)
              Text(
                centerText,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    ],
  );
}
