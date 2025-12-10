import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents an item displayed on the canvas.
class CanvasItem {
  final String id;
  final String widgetName;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  CanvasItem({
    required this.id,
    required this.widgetName,
    required this.data,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  CanvasItem copyWith({
    String? id,
    String? widgetName,
    Map<String, dynamic>? data,
    DateTime? createdAt,
  }) {
    return CanvasItem(
      id: id ?? this.id,
      widgetName: widgetName ?? this.widgetName,
      data: data ?? this.data,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// State for the canvas.
class CanvasState {
  final List<CanvasItem> items;

  const CanvasState({this.items = const []});

  CanvasState copyWith({List<CanvasItem>? items}) {
    return CanvasState(items: items ?? this.items);
  }

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
}

/// Notifier for managing canvas state.
///
/// Supports adding, replacing, and clearing canvas items.
/// Agent can push widgets to canvas via the `canvas_render` tool.
class CanvasNotifier extends StateNotifier<CanvasState> {
  CanvasNotifier() : super(const CanvasState());

  /// Add a new item to the canvas.
  void addItem(String widgetName, Map<String, dynamic> data) {
    final item = CanvasItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      widgetName: widgetName,
      data: data,
    );
    state = state.copyWith(items: [...state.items, item]);
  }

  /// Replace all items with a single new item.
  void replaceAll(String widgetName, Map<String, dynamic> data) {
    final item = CanvasItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      widgetName: widgetName,
      data: data,
    );
    state = state.copyWith(items: [item]);
  }

  /// Clear all items from the canvas.
  void clear() {
    state = const CanvasState();
  }

  /// Remove a specific item by ID.
  void removeItem(String id) {
    state = state.copyWith(
      items: state.items.where((item) => item.id != id).toList(),
    );
  }

  /// Update an existing item's data.
  void updateItem(String id, Map<String, dynamic> newData) {
    state = state.copyWith(
      items: state.items.map((item) {
        if (item.id == id) {
          return item.copyWith(data: {...item.data, ...newData});
        }
        return item;
      }).toList(),
    );
  }
}

/// Provider for canvas state.
final canvasProvider = StateNotifierProvider<CanvasNotifier, CanvasState>((
  ref,
) {
  return CanvasNotifier();
});
