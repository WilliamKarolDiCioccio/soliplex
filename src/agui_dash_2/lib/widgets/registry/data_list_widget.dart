import 'package:flutter/material.dart';

/// DataList widget for displaying key-value pairs in a list format.
class DataListWidget extends StatelessWidget {
  final List<DataListItem> items;

  const DataListWidget({super.key, required this.items});

  /// Create from JSON data.
  ///
  /// Expected data format:
  /// ```json
  /// {
  ///   "items": [
  ///     {"title": "Name", "value": "John Doe"},
  ///     {"title": "Email", "value": "john@example.com"}
  ///   ]
  /// }
  /// ```
  factory DataListWidget.fromData(
    Map<String, dynamic> data,
    void Function(String, Map<String, dynamic>)? onEvent,
  ) {
    final itemsList = data['items'] as List<dynamic>? ?? [];
    return DataListWidget(
      items: itemsList.map((item) {
        final map = item as Map<String, dynamic>;
        return DataListItem(
          title: map['title'] as String? ?? '',
          value: map['value']?.toString() ?? '',
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
