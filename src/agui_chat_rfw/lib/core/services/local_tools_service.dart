import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Result of a local tool execution.
class LocalToolResult {
  final String toolCallId;
  final String toolName;
  final bool success;
  final Map<String, dynamic> result;
  final String? error;

  LocalToolResult({
    required this.toolCallId,
    required this.toolName,
    required this.success,
    required this.result,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'tool_call_id': toolCallId,
        'tool_name': toolName,
        'success': success,
        'result': result,
        if (error != null) 'error': error,
      };

  @override
  String toString() => 'LocalToolResult($toolName: ${success ? "success" : "error: $error"})';
}

/// Definition of a local tool.
class LocalToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> args) execute;

  const LocalToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  /// Convert to AG-UI tool format for sending to server.
  Map<String, dynamic> toAgUiTool() => {
        'name': name,
        'description': description,
        'parameters': parameters,
      };
}

/// Service for managing and executing local (client-side) tools.
///
/// Local tools are executed on the client instead of the server,
/// enabling access to device capabilities like GPS, camera, etc.
class LocalToolsService {
  LocalToolsService._();

  static final LocalToolsService _instance = LocalToolsService._();
  static LocalToolsService get instance => _instance;

  /// Registry of available local tools.
  final Map<String, LocalToolDefinition> _tools = {};

  /// Stream controller for tool execution results.
  final _resultController = StreamController<LocalToolResult>.broadcast();

  /// Stream of tool execution results.
  Stream<LocalToolResult> get results => _resultController.stream;

  /// Initialize with default tools.
  void initialize() {
    // Register the get_my_location tool
    registerTool(_createGetMyLocationTool());

    // Register the genui_render tool (for dynamic widget rendering)
    registerTool(_createGenUiRenderTool());

    debugPrint('LocalToolsService: Initialized with ${_tools.length} tools');
  }

  /// Register a local tool.
  void registerTool(LocalToolDefinition tool) {
    _tools[tool.name] = tool;
    debugPrint('LocalToolsService: Registered tool "${tool.name}"');
  }

  /// Check if a tool is registered locally.
  bool hasLocalTool(String toolName) => _tools.containsKey(toolName);

  /// Get all registered tool definitions.
  List<LocalToolDefinition> get tools => _tools.values.toList();

  /// Get tool definitions in AG-UI format.
  List<Map<String, dynamic>> getAgUiToolDefinitions() {
    return _tools.values.map((t) => t.toAgUiTool()).toList();
  }

  /// Execute a local tool.
  ///
  /// Returns a [LocalToolResult] with the execution result.
  Future<LocalToolResult> executeTool(
    String toolCallId,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    final tool = _tools[toolName];
    if (tool == null) {
      final result = LocalToolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        success: false,
        result: {},
        error: 'Unknown local tool: $toolName',
      );
      _resultController.add(result);
      return result;
    }

    debugPrint('LocalToolsService: Executing tool "$toolName" with args: $arguments');

    try {
      final resultData = await tool.execute(arguments);
      final result = LocalToolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        success: true,
        result: resultData,
      );
      _resultController.add(result);
      debugPrint('LocalToolsService: Tool "$toolName" completed successfully');
      return result;
    } catch (e, stackTrace) {
      debugPrint('LocalToolsService: Tool "$toolName" failed: $e\n$stackTrace');
      final result = LocalToolResult(
        toolCallId: toolCallId,
        toolName: toolName,
        success: false,
        result: {},
        error: e.toString(),
      );
      _resultController.add(result);
      return result;
    }
  }

  /// Create the get_my_location tool definition.
  LocalToolDefinition _createGetMyLocationTool() {
    return LocalToolDefinition(
      name: 'get_my_location',
      description: 'Get the current GPS location of the device. Returns latitude, longitude, accuracy, and other location data.',
      parameters: {
        'type': 'object',
        'properties': {
          'high_accuracy': {
            'type': 'boolean',
            'description': 'Whether to request high accuracy GPS (may take longer)',
            'default': false,
          },
        },
        'required': [],
      },
      execute: _executeGetMyLocation,
    );
  }

  /// Execute the get_my_location tool.
  Future<Map<String, dynamic>> _executeGetMyLocation(Map<String, dynamic> args) async {
    final highAccuracy = args['high_accuracy'] as bool? ?? false;

    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable location services.');
    }

    // Check/request permission
    var permission = await Geolocator.checkPermission();
    bool justGrantedPermission = false;
    if (permission == LocationPermission.denied) {
      debugPrint('LocalToolsService: Requesting location permission...');
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied. Please grant location access.');
      }
      // Permission was just granted - macOS needs time to propagate
      justGrantedPermission = true;
      debugPrint('LocalToolsService: Permission granted, waiting for system to propagate...');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied. '
        'Please enable in System Preferences > Security & Privacy > Privacy > Location Services.',
      );
    }

    // Get current position with retry for freshly granted permissions
    debugPrint('LocalToolsService: Getting current position (highAccuracy=$highAccuracy)...');

    Position? position;
    int retryCount = justGrantedPermission ? 3 : 1;
    Exception? lastError;

    for (int attempt = 1; attempt <= retryCount; attempt++) {
      try {
        // Small delay after permission grant to let macOS propagate
        if (justGrantedPermission && attempt == 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: highAccuracy ? LocationAccuracy.best : LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 15),
          ),
        );
        break; // Success!
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('LocalToolsService: Attempt $attempt failed: $e');

        if (attempt < retryCount) {
          // Wait before retry - permission may still be propagating
          debugPrint('LocalToolsService: Retrying in 1 second...');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    if (position == null) {
      throw lastError ?? Exception('Failed to get location');
    }

    debugPrint('LocalToolsService: Got position: ${position.latitude}, ${position.longitude}');

    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'altitude': position.altitude,
      'speed': position.speed,
      'speed_accuracy': position.speedAccuracy,
      'heading': position.heading,
      'heading_accuracy': position.headingAccuracy,
      'timestamp': position.timestamp.toIso8601String(),
      'is_mocked': position.isMocked,
    };
  }

  /// Create the genui_render tool definition.
  ///
  /// This tool allows the agent to render dynamic UI widgets using RFW.
  /// Unlike other local tools, this one does NOT send a result back to the server.
  /// The widget is rendered directly in the chat UI.
  LocalToolDefinition _createGenUiRenderTool() {
    return LocalToolDefinition(
      name: 'genui_render',
      description: '''Render a dynamic UI widget in the chat. Use this to display interactive elements like buttons, forms, charts, or data cards.

The widget_name should match a widget defined in the library_text.
The library_text uses RFW (Remote Flutter Widgets) format with these imports:
- import core.widgets; (Container, Column, Row, Text, etc.)
- import material; (ElevatedButton, Card, etc.)

Example library_text:
```
import core.widgets;
import material;

widget MyButton = Container(
  padding: [16.0, 16.0, 16.0, 16.0],
  child: ElevatedButton(
    onPressed: event "button_clicked" {},
    child: Text(text: "Click Me"),
  ),
);
```

The data parameter can be used to pass dynamic values to the widget.''',
      parameters: {
        'type': 'object',
        'properties': {
          'widget_name': {
            'type': 'string',
            'description': 'Name of the widget to render (must match a widget defined in library_text)',
          },
          'library_text': {
            'type': 'string',
            'description': 'RFW library text defining the widget',
          },
          'library_name': {
            'type': 'string',
            'description': 'Name for the library namespace (default: "agent")',
            'default': 'agent',
          },
          'data': {
            'type': 'object',
            'description': 'Dynamic data to pass to the widget',
            'default': {},
          },
        },
        'required': ['widget_name', 'library_text'],
      },
      // This execute function is never actually called - genui_render is
      // handled specially in chat_screen.dart to render widgets directly
      execute: (args) async => {'rendered': true},
    );
  }

  void dispose() {
    _resultController.close();
  }
}

/// Riverpod provider for LocalToolsService.
final localToolsServiceProvider = Provider<LocalToolsService>((ref) {
  final service = LocalToolsService.instance;
  service.initialize();
  return service;
});
