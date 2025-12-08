import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart';

// Chart widgets
import 'charts/local_line_chart.dart';
import 'charts/local_bar_chart.dart';
import 'charts/local_pie_chart.dart';

// Media widgets
import 'media/local_svg_image.dart';
import 'media/local_network_image.dart';

/// Creates the local widget library for custom app-specific widgets.
///
/// These widgets are registered with the RFW runtime and can be referenced
/// by remote widget definitions. They bridge the gap between RFW's limited
/// widget set and complex Flutter widgets like charts, maps, etc.
LocalWidgetLibrary createLocalWidgets() {
  return LocalWidgetLibrary(<String, LocalWidgetBuilder>{
    // Placeholder widget for loading states
    'LoadingIndicator': (BuildContext context, DataSource source) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    },

    // Error display widget
    'ErrorDisplay': (BuildContext context, DataSource source) {
      final message = source.v<String>(<Object>['message']) ?? 'An error occurred';
      final color = source.v<int>(<Object>['color']);

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: color != null ? Color(color) : Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color != null ? Color(color) : Colors.red.shade700),
              ),
            ),
          ],
        ),
      );
    },

    // Info card widget
    'InfoCard': (BuildContext context, DataSource source) {
      final title = source.v<String>(<Object>['title']) ?? '';
      final subtitle = source.v<String>(<Object>['subtitle']);
      final icon = source.v<int>(<Object>['icon']);
      final color = source.v<int>(<Object>['color']);
      final baseColor = color != null ? Color(color) : Colors.blue;

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (icon != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: baseColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    IconData(icon, fontFamily: 'MaterialIcons'),
                    color: baseColor,
                  ),
                ),
              if (icon != null) const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },

    // Action button with event callback
    'ActionButton': (BuildContext context, DataSource source) {
      final label = source.v<String>(<Object>['label']) ?? 'Action';
      final color = source.v<int>(<Object>['color']);

      return ElevatedButton(
        style: color != null
            ? ElevatedButton.styleFrom(backgroundColor: Color(color))
            : null,
        onPressed: source.voidHandler(<Object>['onPressed']),
        child: Text(label),
      );
    },

    // Data list widget
    'DataList': (BuildContext context, DataSource source) {
      final itemCount = source.length(<Object>['items']);

      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final title = source.v<String>(<Object>['items', index, 'title']) ?? '';
          final value = source.v<String>(<Object>['items', index, 'value']) ?? '';

          return ListTile(
            title: Text(title),
            trailing: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        },
      );
    },

    // Metric display widget
    'MetricDisplay': (BuildContext context, DataSource source) {
      final label = source.v<String>(<Object>['label']) ?? '';
      final value = source.v<String>(<Object>['value']) ?? '';
      final unit = source.v<String>(<Object>['unit']);
      final trend = source.v<String>(<Object>['trend']); // 'up', 'down', 'neutral'
      final color = source.v<int>(<Object>['color']);

      Color trendColor = Colors.grey;
      IconData trendIcon = Icons.remove;
      if (trend == 'up') {
        trendColor = Colors.green;
        trendIcon = Icons.trending_up;
      } else if (trend == 'down') {
        trendColor = Colors.red;
        trendIcon = Icons.trending_down;
      }

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: color != null ? Color(color) : null,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                  const Spacer(),
                  if (trend != null)
                    Icon(
                      trendIcon,
                      color: trendColor,
                      size: 24,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },

    // Progress indicator widget
    'ProgressCard': (BuildContext context, DataSource source) {
      final label = source.v<String>(<Object>['label']) ?? '';
      final progress = source.v<double>(<Object>['progress']) ?? 0.0;
      final color = source.v<int>(<Object>['color']);

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label),
                  Text('${(progress * 100).toInt()}%'),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(
                  color != null ? Color(color) : Colors.blue,
                ),
              ),
            ],
          ),
        ),
      );
    },

    // ============================================
    // Chart Widgets (fl_chart integration)
    // ============================================

    // Line chart for time series and continuous data
    'LineChart': buildLocalLineChart,

    // Bar chart for categorical comparisons
    'BarChart': buildLocalBarChart,

    // Pie/donut chart for proportional data
    'PieChart': buildLocalPieChart,

    // ============================================
    // Media Widgets
    // ============================================

    // SVG image (asset or network with security validation)
    'SvgImage': buildLocalSvgImage,

    // Network image with caching and SSRF prevention
    'NetworkImage': buildLocalNetworkImage,
  });
}
