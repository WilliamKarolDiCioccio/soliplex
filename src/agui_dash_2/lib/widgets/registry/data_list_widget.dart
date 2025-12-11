import 'package:flutter/material.dart';

/// DataList widget for displaying key-value pairs in a list format.
class DataListWidget extends StatelessWidget {
  final List<DataListItem> items;

  const DataListWidget({super.key, required this.items});

  /// Create from JSON data.
  ///
  /// Supports multiple data formats:
  ///
  /// Format 1 - items array with title/value:
  /// ```json
  /// {
  ///   "items": [
  ///     {"title": "Name", "value": "John Doe"},
  ///     {"title": "Email", "value": "john@example.com"}
  ///   ]
  /// }
  /// ```
  ///
  /// Format 2 - items array with title/subtitle (e.g., user lists):
  /// ```json
  /// {
  ///   "items": [
  ///     {"id": "u1", "title": "John Smith", "subtitle": "Engineering Lead"}
  ///   ]
  /// }
  /// ```
  ///
  /// Format 3 - bare array at root:
  /// ```json
  /// [
  ///   {"title": "John Smith", "subtitle": "Engineering Lead"}
  /// ]
  /// ```
  factory DataListWidget.fromData(
    Map<String, dynamic> data,
    void Function(String, Map<String, dynamic>)? onEvent,
  ) {
    // Handle items either as a nested 'items' key or at root level
    List<dynamic> itemsList;
    if (data.containsKey('items')) {
      itemsList = data['items'] as List<dynamic>? ?? [];
    } else if (data.containsKey('selected')) {
      // Handle SearchWidget selection format
      itemsList = data['selected'] as List<dynamic>? ?? [];
    } else {
      itemsList = [];
    }

    return DataListWidget(
      items: itemsList.map((item) {
        final map = item as Map<String, dynamic>;
        // Support multiple field names for flexibility:
        // - title: primary display text
        // - value OR subtitle: secondary display text
        final title = map['title'] as String? ??
            map['name'] as String? ??
            map['label'] as String? ??
            '';
        final value = map['value']?.toString() ??
            map['subtitle']?.toString() ??
            map['description']?.toString() ??
            '';
        return DataListItem(
          title: title,
          value: value,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            title: Text(item.title),
            trailing: Text(
              item.value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        },
      ),
    );
  }
}

/// A single item in a DataList.
class DataListItem {
  final String title;
  final String value;

  const DataListItem({required this.title, required this.value});
}
