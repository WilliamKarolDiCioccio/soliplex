import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart';

import '../../../core/utils/security_validator.dart';

/// LocalLineChart - RFW wrapper for fl_chart LineChart.
///
/// Maps RFW data format to FlSpot objects for line chart rendering.
///
/// Expected data format:
/// ```
/// {
///   dataPoints: [{x: 0, y: 10}, {x: 1, y: 20}, ...],
///   color: 0xFF2196F3,          // optional, line color
///   strokeWidth: 3.0,           // optional, line width
///   fillColor: 0x442196F3,      // optional, area fill color
///   showDots: true,             // optional, show data points
///   curved: true,               // optional, smooth curves
///   minX: 0, maxX: 10,          // optional, axis bounds
///   minY: 0, maxY: 100,
///   showGrid: true,             // optional, show grid lines
///   title: "Sales Data",        // optional, chart title
/// }
/// ```
Widget buildLocalLineChart(BuildContext context, DataSource source) {
  // Extract data points
  final pointCount = source.length(<Object>['dataPoints']);
  final spots = <FlSpot>[];

  for (var i = 0; i < pointCount; i++) {
    final x = source.v<double>(<Object>['dataPoints', i, 'x']);
    final y = source.v<double>(<Object>['dataPoints', i, 'y']);

    if (x != null && y != null) {
      // Validate chart values for security
      if (SecurityValidator.isValidChartValue(x) &&
          SecurityValidator.isValidChartValue(y)) {
        spots.add(FlSpot(x, y));
      }
    }
  }

  if (spots.isEmpty) {
    return const Center(
      child: Text('No valid data points', style: TextStyle(color: Colors.grey)),
    );
  }

  // Extract styling options
  final colorValue = source.v<int>(<Object>['color']);
  final lineColor = colorValue != null ? Color(colorValue) : Colors.blue;

  final strokeWidth = source.v<double>(<Object>['strokeWidth']) ?? 3.0;

  final fillColorValue = source.v<int>(<Object>['fillColor']);
  final fillColor = fillColorValue != null ? Color(fillColorValue) : null;

  final showDots = source.v<bool>(<Object>['showDots']) ?? false;
  final curved = source.v<bool>(<Object>['curved']) ?? true;
  final showGrid = source.v<bool>(<Object>['showGrid']) ?? true;

  // Axis bounds
  final minX = source.v<double>(<Object>['minX']);
  final maxX = source.v<double>(<Object>['maxX']);
  final minY = source.v<double>(<Object>['minY']);
  final maxY = source.v<double>(<Object>['maxY']);

  // Title
  final title = source.v<String>(<Object>['title']);

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
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(show: showGrid),
            titlesData: const FlTitlesData(
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: Colors.grey.shade300),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: curved,
                color: lineColor,
                barWidth: strokeWidth,
                isStrokeCapRound: true,
                dotData: FlDotData(show: showDots),
                belowBarData: fillColor != null
                    ? BarAreaData(
                        show: true,
                        color: fillColor,
                      )
                    : BarAreaData(show: false),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    return LineTooltipItem(
                      spot.y.toStringAsFixed(1),
                      TextStyle(
                        color: lineColor,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
