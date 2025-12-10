import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../infrastructure/quick_agui/thread.dart';
import 'local_tools_service.dart';

/// Configuration for AG-UI service.
class AgUiServiceConfig {
  final String baseUrl;
  final String roomId;
  final Duration timeout;
  final Map<String, String>? headers;

  const AgUiServiceConfig({
    required this.baseUrl,
    required this.roomId,
    this.timeout = const Duration(seconds: 30),
    this.headers,
  });

  /// Base endpoint for the room
  String get roomEndpoint => '$baseUrl/rooms/$roomId/agui';
}

/// Connection state for the AG-UI service.
enum AgUiConnectionState {
  disconnected,
  connecting,
  connected,
  streaming,
  error,
}

/// Callback for UI tool handlers (canvas_render, genui_render).
typedef UiToolHandler =
    Future<Map<String, dynamic>> Function(
      String toolName,
      Map<String, dynamic> args,
    );

/// AG-UI Service - manages communication with the AG-UI server using Thread.
///
/// Uses the quick_agui Thread class for:
/// - Message history management
/// - Tool call handling
/// - Event streaming
class AgUiService extends ChangeNotifier {
  AgUiServiceConfig? _config;
  final http.Client _httpClient = http.Client();
  AgUiConnectionState _state = AgUiConnectionState.disconnected;
  String? _lastError;

  Thread? _thread;
  String? _currentRunId;

  // AG-UI client for SSE streaming
  ag_ui.AgUiClient? _agUiClient;

  // Handler for UI tools (canvas_render, genui_render)
  UiToolHandler? _uiToolHandler;

  /// Tools that should be handled by the UI layer instead of LocalToolsService.
  static const _uiTools = {'canvas_render', 'genui_render'};

  AgUiConnectionState get state => _state;
  String? get lastError => _lastError;
  String? get threadId => _thread?.id;
  String? get runId => _currentRunId;
  bool get isConfigured => _config != null;
  String? get currentRoomId => _config?.roomId;

  /// Stream of all AG-UI events (for UI to listen to).
  Stream<ag_ui.BaseEvent>? get eventsStream => _thread?.stepsStream;

  /// Stream of messages.
  Stream<ag_ui.Message>? get messagesStream => _thread?.messageStream;

  /// Stream of state updates.
  Stream<ag_ui.State>? get stateStream => _thread?.stateStream;

  /// Configure the AG-UI service with server details.
  void configure(AgUiServiceConfig config) {
    // Skip if config hasn't changed
    if (_config?.baseUrl == config.baseUrl &&
        _config?.roomId == config.roomId) {
      return;
    }

    debugPrint('AgUiService: Configuring for room "${config.roomId}"');
    _config = config;
    _state = AgUiConnectionState.disconnected;
    _lastError = null;

    // Reset thread when room changes
    _thread?.dispose();
    _thread = null;
    _currentRunId = null;

    // Create AG-UI client
    _agUiClient = ag_ui.AgUiClient(
      config: ag_ui.AgUiClientConfig(baseUrl: config.baseUrl),
    );

    notifyListeners();
  }

  /// Create a new thread on the server.
  Future<(String, String)> _createThread() async {
    final response = await _httpClient.post(
      Uri.parse(_config!.roomEndpoint),
      headers: {'Content-Type': 'application/json', ...?_config!.headers},
      body: '{}',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to create thread: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final threadId = data['thread_id'] as String?;
    if (threadId == null) {
      throw Exception('Server did not return thread_id');
    }

    // Server auto-creates initial run
    final runs = data['runs'] as Map<String, dynamic>?;
    if (runs == null || runs.isEmpty) {
      throw Exception('Server did not return any runs');
    }
    final runId = runs.keys.first;

    debugPrint('AG-UI: Created thread: $threadId with initial run: $runId');
    return (threadId, runId);
  }

  /// Create a new run for the given thread.
  Future<String> _createRun(String threadId) async {
    final response = await _httpClient.post(
      Uri.parse('${_config!.roomEndpoint}/$threadId'),
      headers: {'Content-Type': 'application/json', ...?_config!.headers},
      body: '{}',
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to create run: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final runId = data['run_id'] as String?;
    if (runId == null) {
      throw Exception('Server did not return run_id');
    }

    debugPrint('AG-UI: Created run: $runId');
    return runId;
  }

  /// Register local tools with the thread.
  void _registerTools(LocalToolsService localToolsService) {
    if (_thread == null) return;

    for (final toolDef in localToolsService.tools) {
      final agTool = ag_ui.Tool(
        name: toolDef.name,
        description: toolDef.description,
        parameters: toolDef.parameters,
      );

      _thread!.addTool(agTool, (call) async {
        debugPrint('AG-UI: Tool executor callback for ${call.function.name}');

        // Parse arguments
        Map<String, dynamic> args = {};
        try {
          if (call.function.arguments.isNotEmpty) {
            args = jsonDecode(call.function.arguments) as Map<String, dynamic>;
          }
        } catch (e) {
          debugPrint('AG-UI: Failed to parse tool args: $e');
        }

        // Check if this is a UI tool that needs special handling
        if (_uiTools.contains(call.function.name) && _uiToolHandler != null) {
          debugPrint('AG-UI: Routing ${call.function.name} to UI handler');
          try {
            final result = await _uiToolHandler!(call.function.name, args);
            return jsonEncode(result);
          } catch (e) {
            debugPrint('AG-UI: UI handler error: $e');
            return jsonEncode({'error': e.toString()});
          }
        }

        // Execute the tool via LocalToolsService
        debugPrint('AG-UI: Calling localToolsService.executeTool...');
        final result = await localToolsService.executeTool(
          call.id,
          call.function.name,
          args,
        );
        debugPrint('AG-UI: Tool execution returned: success=${result.success}');

        if (result.success) {
          final json = jsonEncode(result.result);
          debugPrint('AG-UI: Returning success JSON (${json.length} chars)');
          return json;
        } else {
          debugPrint('AG-UI: Returning error: ${result.error}');
          return jsonEncode({'error': result.error});
        }
      });
    }
  }

  /// Send a user message and get the agent's response.
  ///
  /// Returns a stream of events for the UI to process.
  Stream<ag_ui.BaseEvent> sendMessage(
    String userMessage, {
    LocalToolsService? localToolsService,
  }) async* {
    if (_config == null || _agUiClient == null) {
      throw StateError('AgUiService not configured. Call configure() first.');
    }

    _state = AgUiConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      // Create thread if needed
      if (_thread == null) {
        final (threadId, runId) = await _createThread();
        _currentRunId = runId;

        _thread = Thread(id: threadId, client: _agUiClient!);

        // Register tools
        if (localToolsService != null) {
          _registerTools(localToolsService);
        }
      } else {
        // Create new run for existing thread
        _currentRunId = await _createRun(_thread!.id);
      }

      _state = AgUiConnectionState.streaming;
      notifyListeners();

      // Add user message
      final userMsg = ag_ui.UserMessage(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        content: userMessage,
      );

      // Generate the endpoint
      final endpoint =
          'rooms/${_config!.roomId}/agui/${_thread!.id}/$_currentRunId';
      debugPrint('AG-UI: Starting run at $endpoint');

      // Start the run - Thread handles the event loop
      var toolResults = await _thread!.startRun(
        endpoint: endpoint,
        runId: _currentRunId!,
        messages: [userMsg],
      );

      // Yield events from the thread's stream
      // Note: Events are already being processed by Thread.startRun()
      // We yield from the stepsStream for UI updates
      await for (final event in _thread!.stepsStream) {
        yield event;
      }

      // Handle tool result loop
      while (toolResults.isNotEmpty) {
        debugPrint('AG-UI: Processing ${toolResults.length} tool results');

        _currentRunId = await _createRun(_thread!.id);
        final newEndpoint =
            'rooms/${_config!.roomId}/agui/${_thread!.id}/$_currentRunId';

        toolResults = await _thread!.sendToolResults(
          endpoint: newEndpoint,
          runId: _currentRunId!,
          toolMessages: toolResults,
        );
      }

      _state = AgUiConnectionState.connected;
      notifyListeners();
    } catch (e, stackTrace) {
      _state = AgUiConnectionState.error;
      _lastError = e.toString();
      debugPrint('AgUiService error: $e\n$stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  /// Simplified message sending that handles tool loop internally.
  ///
  /// This is the main method to use - it handles the full conversation flow
  /// including tool execution and returns events as they occur.
  ///
  /// [uiToolHandler] is called for canvas_render and genui_render tools
  /// which need access to UI state (Riverpod providers).
  Future<void> chat(
    String userMessage, {
    required LocalToolsService localToolsService,
    required void Function(ag_ui.BaseEvent event) onEvent,
    UiToolHandler? uiToolHandler,
  }) async {
    // Store UI tool handler for use in tool executor
    _uiToolHandler = uiToolHandler;
    if (_config == null || _agUiClient == null) {
      throw StateError('AgUiService not configured. Call configure() first.');
    }

    _state = AgUiConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      // Create thread if needed
      if (_thread == null) {
        final (threadId, runId) = await _createThread();
        _currentRunId = runId;

        _thread = Thread(id: threadId, client: _agUiClient!);
      } else {
        // Create new run for existing thread
        _currentRunId = await _createRun(_thread!.id);
      }

      // Always register tools (thread may have been resumed without tools)
      _registerTools(localToolsService);

      _state = AgUiConnectionState.streaming;
      notifyListeners();

      // Listen to events stream
      final subscription = _thread!.stepsStream.listen(onEvent);

      // Add user message
      final userMsg = ag_ui.UserMessage(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        content: userMessage,
      );

      // Generate the endpoint
      final endpoint =
          'rooms/${_config!.roomId}/agui/${_thread!.id}/$_currentRunId';
      debugPrint('AG-UI: Starting run at $endpoint');

      // Start the run
      var toolResults = await _thread!.startRun(
        endpoint: endpoint,
        runId: _currentRunId!,
        messages: [userMsg],
      );

      // Handle tool result loop
      while (toolResults.isNotEmpty) {
        debugPrint('AG-UI: Processing ${toolResults.length} tool results');

        _currentRunId = await _createRun(_thread!.id);
        final newEndpoint =
            'rooms/${_config!.roomId}/agui/${_thread!.id}/$_currentRunId';

        toolResults = await _thread!.sendToolResults(
          endpoint: newEndpoint,
          runId: _currentRunId!,
          toolMessages: toolResults,
        );
      }

      await subscription.cancel();

      _state = AgUiConnectionState.connected;
      notifyListeners();
    } catch (e, stackTrace) {
      _state = AgUiConnectionState.error;
      _lastError = e.toString();
      debugPrint('AgUiService error: $e\n$stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  /// Resume an existing thread by ID.
  ///
  /// This sets the service to continue conversation on an existing thread.
  /// Note: Message history is not loaded (AG-UI is stateless per-run).
  /// The next message sent will continue on this thread.
  void resumeThread(String threadId) {
    if (_config == null || _agUiClient == null) {
      throw StateError('AgUiService not configured. Call configure() first.');
    }

    debugPrint('AgUiService: Resuming thread $threadId');

    // Dispose old thread if exists
    _thread?.dispose();

    // Create new Thread instance with the existing ID
    _thread = Thread(id: threadId, client: _agUiClient!);
    _currentRunId = null;

    _state = AgUiConnectionState.connected;
    notifyListeners();
  }

  /// Reset the conversation (clear thread).
  void resetConversation() {
    _thread?.reset();
    _thread?.dispose();
    _thread = null;
    _currentRunId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _thread?.dispose();
    _httpClient.close();
    super.dispose();
  }
}

/// Riverpod provider for AgUiService.
final agUiServiceProvider = ChangeNotifierProvider<AgUiService>((ref) {
  return AgUiService();
});

/// Provider for AG-UI configuration.
final agUiConfigProvider = StateProvider<AgUiServiceConfig?>((ref) => null);

/// Combined provider that auto-configures AgUiService when config changes.
final configuredAgUiServiceProvider = Provider<AgUiService>((ref) {
  final service = ref.watch(agUiServiceProvider);

  ref.listen<AgUiServiceConfig?>(agUiConfigProvider, (previous, next) {
    if (next != null &&
        (previous?.roomId != next.roomId ||
            previous?.baseUrl != next.baseUrl)) {
      Future.microtask(() => service.configure(next));
    }
  });

  final config = ref.read(agUiConfigProvider);
  if (config != null && !service.isConfigured) {
    Future.microtask(() => service.configure(config));
  }

  return service;
});
