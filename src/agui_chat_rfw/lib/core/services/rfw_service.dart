import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw/formats.dart' as rfw_formats;

import '../utils/security_validator.dart';
import '../../widgets/local/local_widget_library.dart';

/// RFW Runtime Service - manages the Remote Flutter Widgets runtime.
///
/// This singleton service maintains the lifecycle of the RFW Runtime,
/// handles widget library registration, and provides secure decoding
/// of remote widget payloads.
class RfwService {
  RfwService._();

  static final RfwService _instance = RfwService._();
  static RfwService get instance => _instance;

  late final Runtime _runtime;
  bool _initialized = false;

  Runtime get runtime => _runtime;
  bool get isInitialized => _initialized;

  /// Initialize the RFW runtime with core and local widget libraries.
  void initialize() {
    if (_initialized) return;

    _runtime = Runtime();

    // Register core Flutter widgets
    _runtime.update(
      const LibraryName(<String>['core', 'widgets']),
      createCoreWidgets(),
    );

    // Register Material Design widgets
    _runtime.update(
      const LibraryName(<String>['material']),
      createMaterialWidgets(),
    );

    // Register custom local widgets (charts, forms, etc.)
    _runtime.update(
      const LibraryName(<String>['local']),
      createLocalWidgets(),
    );

    _initialized = true;
  }

  /// Decode and validate a binary RFW library blob.
  ///
  /// Returns null if the payload fails validation (depth limit exceeded,
  /// disallowed widgets, etc.)
  RemoteWidgetLibrary? decodeLibrary(Uint8List blob) {
    try {
      final library = decodeLibraryBlob(blob);

      // Validate the decoded library
      if (!SecurityValidator.validateLibrary(library)) {
        debugPrint('RfwService: Library failed security validation');
        return null;
      }

      return library;
    } catch (e) {
      debugPrint('RfwService: Failed to decode library blob: $e');
      return null;
    }
  }

  /// Parse RFW text format (.rfwtxt) into a library.
  ///
  /// Useful for development/debugging. In production, prefer binary format.
  RemoteWidgetLibrary? parseTextLibrary(String source) {
    try {
      final library = rfw_formats.parseLibraryFile(source);

      if (!SecurityValidator.validateLibrary(library)) {
        debugPrint('RfwService: Text library failed security validation');
        return null;
      }

      return library;
    } catch (e) {
      debugPrint('RfwService: Failed to parse text library: $e');
      return null;
    }
  }

  /// Register a remote widget library with the runtime.
  void registerLibrary(LibraryName name, RemoteWidgetLibrary library) {
    _runtime.update(name, library);
  }

  /// Create a DynamicContent instance for a specific message.
  ///
  /// Data is stored at root level so RFW can access via `data.fieldName`.
  DynamicContent createDynamicContent([Map<String, Object?>? initialData]) {
    final content = DynamicContent();
    if (initialData != null) {
      // Store each key at root level for direct access in RFW
      for (final entry in initialData.entries) {
        if (entry.value != null) {
          content.update(entry.key, entry.value!);
        }
      }
    }
    return content;
  }

  /// Update data in a DynamicContent instance.
  void updateContent(DynamicContent content, String key, Object value) {
    content.update(key, value);
  }

  /// Build a RemoteWidget for rendering.
  Widget buildRemoteWidget({
    required RemoteWidgetLibrary library,
    required LibraryName libraryName,
    required String widgetName,
    required DynamicContent data,
    required void Function(String name, DynamicMap arguments) onEvent,
  }) {
    // Register this specific library
    _runtime.update(libraryName, library);

    return RemoteWidget(
      runtime: _runtime,
      data: data,
      widget: FullyQualifiedWidgetName(libraryName, widgetName),
      onEvent: onEvent,
    );
  }
}

/// Riverpod provider for RfwService
final rfwServiceProvider = Provider<RfwService>((ref) {
  final service = RfwService.instance;
  service.initialize();
  return service;
});
