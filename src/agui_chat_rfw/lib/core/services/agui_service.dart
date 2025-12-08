import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'chat_service.dart';
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

/// AG-UI Service - manages SSE communication with the AG-UI server.
///
/// Handles the 2-step flow:
/// 1. POST /rooms/{room_id}/agui → creates thread WITH initial run
/// 2. POST /rooms/{room_id}/agui/{thread_id}/{run_id} → SSE stream
class AgUiService extends ChangeNotifier {
  AgUiServiceConfig? _config;
  final http.Client _httpClient = http.Client();
  AgUiConnectionState _state = AgUiConnectionState.disconnected;
  String? _lastError;
  String? _currentThreadId;
  String? _currentRunId;

  /// Message history for the current conversation (needed for tool results)
  final List<Map<String, dynamic>> _messageHistory = [];

  AgUiConnectionState get state => _state;
  String? get lastError => _lastError;
  String? get threadId => _currentThreadId;
  String? get runId => _currentRunId;
  bool get isConfigured => _config != null;
  String? get currentRoomId => _config?.roomId;

  /// Configure the AG-UI service with server details.
  /// Only reconfigures if the config actually changed.
  void configure(AgUiServiceConfig config) {
    // Skip if config hasn't changed
    if (_config?.baseUrl == config.baseUrl && _config?.roomId == config.roomId) {
      return;
    }

    debugPrint('AgUiService: Configuring for room "${config.roomId}"');
    _config = config;
    _state = AgUiConnectionState.disconnected;
    _lastError = null;
    // Reset thread when room changes
    _currentThreadId = null;
    _currentRunId = null;
    _messageHistory.clear();
    notifyListeners();
  }

  /// Create a new thread on the server.
  /// Server automatically creates an initial run, so returns both (threadId, runId).
  Future<(String, String)> _createThread() async {
    final response = await _httpClient.post(
      Uri.parse(_config!.roomEndpoint),
      headers: {
        'Content-Type': 'application/json',
        ...?_config!.headers,
      },
      body: '{}', // AGUI_NewThreadRequest - empty body for optional metadata
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create thread: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final threadId = data['thread_id'] as String?;
    if (threadId == null) {
      throw Exception('Server did not return thread_id');
    }

    // Server auto-creates initial run - extract run_id from runs map
    final runs = data['runs'] as Map<String, dynamic>?;
    if (runs == null || runs.isEmpty) {
      throw Exception('Server did not return any runs');
    }
    final runId = runs.keys.first;

    debugPrint('AG-UI: Created thread: $threadId with initial run: $runId');
    return (threadId, runId);
  }

  /// Create a new run for the given thread (for subsequent messages).
  Future<String> _createRun(String threadId) async {
    final response = await _httpClient.post(
      Uri.parse('${_config!.roomEndpoint}/$threadId'),
      headers: {
        'Content-Type': 'application/json',
        ...?_config!.headers,
      },
      body: '{}', // AGUI_NewRunRequest - empty body for optional metadata
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create run: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final runId = data['run_id'] as String?;
    if (runId == null) {
      throw Exception('Server did not return run_id');
    }

    debugPrint('AG-UI: Created run: $runId');
    return runId;
  }

  /// Send a user message and stream the agent's response.
  ///
  /// If [localTools] is provided, those tool definitions will be sent to the server.
  Stream<BaseEvent> sendMessage(
    String userMessage, {
    List<Map<String, dynamic>>? localTools,
  }) async* {
    if (_config == null) {
      throw StateError('AgUiService not configured. Call configure() first.');
    }

    _state = AgUiConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      // Step 1: Create thread (with initial run) or new run for existing thread
      if (_currentThreadId == null) {
        final (threadId, runId) = await _createThread();
        _currentThreadId = threadId;
        _currentRunId = runId;
      } else {
        // Create new run for subsequent messages in same thread
        _currentRunId = await _createRun(_currentThreadId!);
      }

      // Step 2: Stream events from the run endpoint
      final runEndpoint = '${_config!.roomEndpoint}/$_currentThreadId/$_currentRunId';
      debugPrint('AG-UI: Streaming from $runEndpoint');

      _state = AgUiConnectionState.streaming;
      notifyListeners();

      // Build user message and add to history
      final userMsg = {
        'role': 'user',
        'id': 'user-${DateTime.now().millisecondsSinceEpoch}',
        'content': userMessage,
      };
      _messageHistory.add(userMsg);

      // Build the AG-UI input - must include forwardedProps!
      final inputJson = {
        'thread_id': _currentThreadId,
        'run_id': _currentRunId,
        'messages': _messageHistory.toList(),
        'tools': localTools ?? <Map<String, dynamic>>[],
        'context': <Map<String, dynamic>>[],
        'state': <String, dynamic>{},
        'forwardedProps': <String, dynamic>{}, // Required by server!
      };

      debugPrint('AG-UI: Sending with ${localTools?.length ?? 0} local tools, ${_messageHistory.length} messages in history');

      // Make the SSE request
      final request = http.Request('POST', Uri.parse(runEndpoint));
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'text/event-stream';
      if (_config!.headers != null) {
        request.headers.addAll(_config!.headers!);
      }
      request.body = jsonEncode(inputJson);

      final streamedResponse = await _httpClient.send(request);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception('SSE request failed: ${streamedResponse.statusCode} $body');
      }

      // Parse SSE stream
      await for (final event in _parseSseStream(streamedResponse.stream)) {
        yield event;
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

  /// Record an assistant message with tool calls in history.
  ///
  /// This must be called when tool calls are received so that
  /// tool results can be properly matched to their tool calls.
  void recordAssistantToolCall({
    required String toolCallId,
    required String toolName,
    required String arguments,
  }) {
    // Add assistant message with tool_calls to history
    // Use camelCase for AG-UI protocol (alias_generator=to_camel)
    final assistantMsg = {
      'role': 'assistant',
      'id': 'assistant-${DateTime.now().millisecondsSinceEpoch}',
      'content': '',
      'toolCalls': [
        {
          'id': toolCallId,
          'type': 'function',
          'function': {
            'name': toolName,
            'arguments': arguments,
          },
        },
      ],
    };
    _messageHistory.add(assistantMsg);
    debugPrint('AG-UI: Recorded assistant tool call in history: $toolCallId');
  }

  /// Send a tool result back to the server and stream the response.
  ///
  /// This is used after executing a local tool to send the result back
  /// and get the agent's continued response.
  ///
  /// If [localTools] is provided, they will be sent so the server can make
  /// additional tool calls if needed.
  Stream<BaseEvent> sendToolResult(
    LocalToolResult toolResult, {
    List<Map<String, dynamic>>? localTools,
  }) async* {
    if (_config == null || _currentThreadId == null || _currentRunId == null) {
      throw StateError('No active conversation. Send a message first.');
    }

    _state = AgUiConnectionState.streaming;
    notifyListeners();

    try {
      final runEndpoint = '${_config!.roomEndpoint}/$_currentThreadId/$_currentRunId';
      debugPrint('AG-UI: Sending tool result for ${toolResult.toolName}');

      // Build tool result message and add to history
      // Use camelCase for AG-UI protocol (alias_generator=to_camel)
      final toolResultMsg = {
        'role': 'tool',
        'id': 'tool-${DateTime.now().millisecondsSinceEpoch}',
        'toolCallId': toolResult.toolCallId,
        'content': jsonEncode(toolResult.result),
      };
      _messageHistory.add(toolResultMsg);

      // Build the input with full message history
      final inputJson = {
        'thread_id': _currentThreadId,
        'run_id': _currentRunId,
        'messages': _messageHistory.toList(),
        'tools': localTools ?? <Map<String, dynamic>>[],
        'context': <Map<String, dynamic>>[],
        'state': <String, dynamic>{},
        'forwardedProps': <String, dynamic>{},
      };

      debugPrint('AG-UI: Sending tool result with ${_messageHistory.length} messages, ${localTools?.length ?? 0} tools');
      debugPrint('AG-UI: Message history: ${jsonEncode(_messageHistory)}');

      final request = http.Request('POST', Uri.parse(runEndpoint));
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'text/event-stream';
      if (_config!.headers != null) {
        request.headers.addAll(_config!.headers!);
      }
      request.body = jsonEncode(inputJson);

      final streamedResponse = await _httpClient.send(request);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception('Tool result request failed: ${streamedResponse.statusCode} $body');
      }

      await for (final event in _parseSseStream(streamedResponse.stream)) {
        yield event;
      }

      _state = AgUiConnectionState.connected;
      notifyListeners();
    } catch (e, stackTrace) {
      _state = AgUiConnectionState.error;
      _lastError = e.toString();
      debugPrint('AgUiService tool result error: $e\n$stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  /// Parse SSE stream into AG-UI events.
  Stream<BaseEvent> _parseSseStream(Stream<List<int>> byteStream) async* {
    final buffer = StringBuffer();

    await for (final chunk in byteStream.transform(utf8.decoder)) {
      buffer.write(chunk);

      // Process complete SSE messages
      var content = buffer.toString();
      while (content.contains('\n\n')) {
        final endIndex = content.indexOf('\n\n');
        final message = content.substring(0, endIndex);
        content = content.substring(endIndex + 2);
        buffer.clear();
        buffer.write(content);

        // Parse SSE message
        final event = _parseSseMessage(message);
        if (event != null) {
          yield event;
        }
      }
    }

    // Handle any remaining content
    if (buffer.isNotEmpty) {
      final event = _parseSseMessage(buffer.toString());
      if (event != null) {
        yield event;
      }
    }
  }

  /// Parse a single SSE message into an AG-UI event.
  BaseEvent? _parseSseMessage(String message) {
    String? eventType;
    String? data;

    for (final line in message.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data = line.substring(5).trim();
      }
    }

    if (data == null || data.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;

      // Add event type to json if not present
      if (eventType != null && !json.containsKey('type')) {
        json['type'] = eventType;
      }

      // Try to parse as a known event type
      try {
        return BaseEvent.fromJson(json);
      } catch (e) {
        // Unknown event type - log and skip
        final type = json['type'] as String? ?? eventType ?? 'UNKNOWN';
        debugPrint('AG-UI: Unknown event type "$type" (skipping)');
        return null;
      }
    } catch (e) {
      debugPrint('AG-UI: Failed to parse event JSON: $e\nData: $data');
      return null;
    }
  }

  /// Reset the conversation (clear thread ID).
  void resetConversation() {
    _currentThreadId = null;
    _currentRunId = null;
    notifyListeners();
  }

  @override
  void dispose() {
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
/// Note: Configuration happens via ref.listen callback, not during build phase.
final configuredAgUiServiceProvider = Provider<AgUiService>((ref) {
  final service = ref.watch(agUiServiceProvider);

  // Listen for config changes - the callback runs after the build phase completes
  ref.listen<AgUiServiceConfig?>(agUiConfigProvider, (previous, next) {
    if (next != null && (previous?.roomId != next.roomId || previous?.baseUrl != next.baseUrl)) {
      // Schedule configuration for after the current build phase
      Future.microtask(() => service.configure(next));
    }
  });

  // Initial configuration if config already exists (scheduled for after build)
  final config = ref.read(agUiConfigProvider);
  if (config != null && !service.isConfigured) {
    Future.microtask(() => service.configure(config));
  }

  return service;
});

/// Extension to process AG-UI events and update chat state.
extension AgUiEventProcessor on ChatNotifier {
  /// Process a stream of AG-UI events and update chat state accordingly.
  Future<void> processAgUiEvents(Stream<BaseEvent> events) async {
    String? currentMessageId;
    String? currentToolCallId;
    final toolCallArgsBuffer = StringBuffer();

    await for (final event in events) {
      debugPrint('AG-UI Event: ${event.runtimeType}');

      switch (event) {
        case RunStartedEvent():
          debugPrint('AG-UI: Run started - ${event.runId}');

        case TextMessageStartEvent():
          currentMessageId = startAgentMessage();
          debugPrint('AG-UI: Text message started, id=$currentMessageId');

        case TextMessageContentEvent():
          if (currentMessageId != null) {
            appendToStreamingMessage(event.delta);
            debugPrint('AG-UI: Text delta: ${event.delta}');
          }

        case TextMessageEndEvent():
          if (currentMessageId != null) {
            finalizeStreamingMessage();
            debugPrint('AG-UI: Text message ended');
            currentMessageId = null;
          }

        case ToolCallStartEvent():
          currentToolCallId = event.toolCallId;
          toolCallArgsBuffer.clear();
          currentMessageId = addLoadingPlaceholder();
          startToolCall(event.toolCallId);
          debugPrint('AG-UI: Tool call started - ${event.toolCallId}');

        case ToolCallArgsEvent():
          if (currentToolCallId != null) {
            toolCallArgsBuffer.write(event.delta);
            appendToolCallArgs(currentToolCallId, event.delta);
            debugPrint('AG-UI: Tool args delta: ${event.delta}');
          }

        case ToolCallEndEvent():
          if (currentToolCallId != null && currentMessageId != null) {
            final argsJson = getToolCallArgs(currentToolCallId);
            if (argsJson != null) {
              debugPrint('AG-UI: Tool call completed with args: $argsJson');
              // TODO: Parse args and create GenUiContent
            }
            clearToolCall(currentToolCallId);
            currentToolCallId = null;
            currentMessageId = null;
          }

        case StateSnapshotEvent():
          debugPrint('AG-UI: State snapshot received');

        case StateDeltaEvent():
          debugPrint('AG-UI: State delta received');

        case RunFinishedEvent():
          debugPrint('AG-UI: Run finished - ${event.runId}');

        case RunErrorEvent():
          addErrorMessage(event.message);
          debugPrint('AG-UI: Run error - ${event.code}: ${event.message}');

        default:
          debugPrint('AG-UI: Unhandled event - ${event.runtimeType}');
      }
    }
  }
}
