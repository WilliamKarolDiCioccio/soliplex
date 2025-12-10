import 'package:flutter/material.dart';

/// InfoCard widget for displaying information with title, subtitle, and optional icon.
class InfoCardWidget extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  const InfoCardWidget({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.onTap,
  });

  /// Create from JSON data.
  ///
  /// Expected data format:
  /// ```json
  /// {
  ///   "title": "Card Title",
  ///   "subtitle": "Optional subtitle",
  ///   "icon": 58751,  // IconData codePoint
  ///   "color": 4280391411  // Color value in ARGB32
  /// }
  /// ```
  factory InfoCardWidget.fromData(
    Map<String, dynamic> data,
    void Function(String, Map<String, dynamic>)? onEvent,
  ) {
    return InfoCardWidget(
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String?,
      icon: data['icon'] != null
          ? IconData(data['icon'] as int, fontFamily: 'MaterialIcons')
          : null,
      color: data['color'] != null ? Color(data['color'] as int) : null,
      onTap: onEvent != null ? () => onEvent('tap', {}) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? Theme.of(context).colorScheme.primary;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: baseColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: baseColor),
                ),
                const SizedBox(width: 16),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
