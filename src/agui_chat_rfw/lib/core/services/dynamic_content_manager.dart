import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rfw/rfw.dart';

import '../utils/security_validator.dart';

/// Manages DynamicContent instances for per-message state in RFW rendering.
///
/// Provides:
/// - Per-message content lifecycle management
/// - Reactive data binding with state events
/// - Partial updates without full widget tree rebuilds
/// - Dirty checking to minimize unnecessary rebuilds
class DynamicContentManager {
  DynamicContentManager._();

  static final DynamicContentManager _instance = DynamicContentManager._();
  static DynamicContentManager get instance => _instance;

  /// Map of message ID -> DynamicContent instance
  final Map<String, _ManagedContent> _contents = {};

  /// Stream controller for content update notifications
  final _updateController = StreamController<ContentUpdate>.broadcast();

  /// Stream of content updates (for debugging/monitoring)
  Stream<ContentUpdate> get updates => _updateController.stream;

  /// Create or retrieve DynamicContent for a message.
  ///
  /// If content already exists for this messageId, returns existing instance.
  /// Otherwise creates a new instance with optional initial data.
  DynamicContent getOrCreate(String messageId, [Map<String, Object?>? initialData]) {
    if (_contents.containsKey(messageId)) {
      return _contents[messageId]!.content;
    }

    final content = DynamicContent();
    if (initialData != null) {
      final sanitized = SecurityValidator.sanitizeDataMap(
        initialData.cast<String, dynamic>(),
      );
      content.update('data', sanitized);
    }

    _contents[messageId] = _ManagedContent(
      content: content,
      createdAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

    debugPrint('DynamicContentManager: Created content for message $messageId');
    return content;
  }

  /// Check if content exists for a message.
  bool hasContent(String messageId) => _contents.containsKey(messageId);

  /// Get existing content for a message, or null if not found.
  DynamicContent? get(String messageId) => _contents[messageId]?.content;

  /// Update data in a message's DynamicContent.
  ///
  /// Performs dirty checking to skip updates if data hasn't changed.
  /// Emits update notification if data changed.
  bool update(String messageId, String key, Object? value) {
    final managed = _contents[messageId];
    if (managed == null) {
      debugPrint('DynamicContentManager: No content for message $messageId');
      return false;
    }

    // Sanitize value if it's a map
    final sanitizedValue = value is Map<String, dynamic>
        ? SecurityValidator.sanitizeDataMap(value)
        : value;

    // Update the content (only if value is non-null)
    if (sanitizedValue != null) {
      managed.content.update(key, sanitizedValue);
    }
    managed.lastUpdated = DateTime.now();
    managed.updateCount++;

    _updateController.add(ContentUpdate(
      messageId: messageId,
      key: key,
      timestamp: managed.lastUpdated,
    ));

    debugPrint('DynamicContentManager: Updated $key for message $messageId');
    return true;
  }

  /// Apply a full state snapshot to a message's content.
  ///
  /// Replaces the 'data' key with the snapshot data.
  bool applySnapshot(String messageId, Map<String, Object?> snapshot) {
    final managed = _contents[messageId];
    if (managed == null) {
      // Auto-create if doesn't exist
      getOrCreate(messageId, snapshot);
      return true;
    }

    final sanitized = SecurityValidator.sanitizeDataMap(
      snapshot.cast<String, dynamic>(),
    );
    managed.content.update('data', sanitized);
    managed.lastUpdated = DateTime.now();
    managed.updateCount++;

    _updateController.add(ContentUpdate(
      messageId: messageId,
      key: 'data',
      timestamp: managed.lastUpdated,
      isSnapshot: true,
    ));

    return true;
  }

  /// Apply a partial delta update to a message's content.
  ///
  /// Merges delta into existing data without replacing unchanged fields.
  bool applyDelta(String messageId, Map<String, Object?> delta) {
    final managed = _contents[messageId];
    if (managed == null) {
      debugPrint('DynamicContentManager: No content for delta on message $messageId');
      return false;
    }

    // Apply each delta field individually
    final sanitized = SecurityValidator.sanitizeDataMap(
      delta.cast<String, dynamic>(),
    );

    for (final entry in sanitized.entries) {
      managed.content.update('data.${entry.key}', entry.value);
    }

    managed.lastUpdated = DateTime.now();
    managed.updateCount++;

    _updateController.add(ContentUpdate(
      messageId: messageId,
      key: 'data',
      timestamp: managed.lastUpdated,
      isDelta: true,
    ));

    return true;
  }

  /// Dispose content for a specific message.
  void dispose(String messageId) {
    if (_contents.remove(messageId) != null) {
      debugPrint('DynamicContentManager: Disposed content for message $messageId');
    }
  }

  /// Dispose all content older than the specified duration.
  ///
  /// Useful for memory management in long-running sessions.
  int disposeOlderThan(Duration age) {
    final threshold = DateTime.now().subtract(age);
    final toRemove = <String>[];

    for (final entry in _contents.entries) {
      if (entry.value.lastUpdated.isBefore(threshold)) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      _contents.remove(id);
    }

    if (toRemove.isNotEmpty) {
      debugPrint('DynamicContentManager: Disposed ${toRemove.length} stale contents');
    }

    return toRemove.length;
  }

  /// Get statistics about managed content.
  ContentManagerStats get stats => ContentManagerStats(
        activeCount: _contents.length,
        totalUpdates: _contents.values.fold(0, (sum, c) => sum + c.updateCount),
        oldestContent: _contents.values.isEmpty
            ? null
            : _contents.values
                .map((c) => c.createdAt)
                .reduce((a, b) => a.isBefore(b) ? a : b),
      );

  /// Clear all managed content.
  void clear() {
    _contents.clear();
    debugPrint('DynamicContentManager: Cleared all content');
  }
}

/// Internal wrapper for managed DynamicContent with metadata.
class _ManagedContent {
  final DynamicContent content;
  final DateTime createdAt;
  DateTime lastUpdated;
  int updateCount = 0;

  _ManagedContent({
    required this.content,
    required this.createdAt,
    required this.lastUpdated,
  });
}

/// Notification of a content update.
class ContentUpdate {
  final String messageId;
  final String key;
  final DateTime timestamp;
  final bool isSnapshot;
  final bool isDelta;

  ContentUpdate({
    required this.messageId,
    required this.key,
    required this.timestamp,
    this.isSnapshot = false,
    this.isDelta = false,
  });

  @override
  String toString() =>
      'ContentUpdate($messageId, $key, snapshot=$isSnapshot, delta=$isDelta)';
}

/// Statistics about the content manager.
class ContentManagerStats {
  final int activeCount;
  final int totalUpdates;
  final DateTime? oldestContent;

  ContentManagerStats({
    required this.activeCount,
    required this.totalUpdates,
    this.oldestContent,
  });

  @override
  String toString() =>
      'ContentManagerStats(active: $activeCount, updates: $totalUpdates)';
}
