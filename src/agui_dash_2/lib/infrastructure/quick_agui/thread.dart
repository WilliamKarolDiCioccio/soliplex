import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ag_ui/ag_ui.dart' as ag_ui;

import 'text_message_buffer.dart';
import 'tool_call_reception_buffer.dart';
import 'tool_call_registry.dart';

/// Callback type for executing client-side tools.
typedef ToolExecutor = Future<String> Function(ag_ui.ToolCall call);

/// Thread manages an AG-UI conversation thread.
///
/// Handles:
/// - Message history
/// - State snapshots and deltas
/// - Tool call registration and execution
/// - Event streaming
class Thread {
  final String id;
  final ag_ui.AgUiClient client;
  final List<ag_ui.Tool> _tools;
  final Map<String, ToolExecutor> _toolExecutors;
  final List<ag_ui.Run> _runs = [];
  final StreamController<ag_ui.Message> _messagesController;
  final StreamController<ag_ui.State> _statesController;
  final StreamController<ag_ui.BaseEvent> _stepsController;

  /// Track if thread has been disposed to prevent adding to closed streams.
  bool _disposed = false;
  bool get isDisposed => _disposed;

  ag_ui.State? currentState;
  final List<ag_ui.Message> messageHistory = [];

  // Per-message text buffers to support concurrent message streams
  final Map<String, TextMessageBuffer> _textBuffers = {};

  Thread({
    required this.id,
    required this.client,
    List<ag_ui.Tool>? tools,
    Map<String, ToolExecutor>? toolExecutors,
  }) : _tools = tools != null ? List.from(tools) : <ag_ui.Tool>[],
       _toolExecutors = toolExecutors != null
           ? Map.from(toolExecutors)
           : <String, ToolExecutor>{},
       _messagesController = StreamController.broadcast(),
       _statesController = StreamController.broadcast(),
       _stepsController = StreamController.broadcast() {
    stateStream.forEach((s) => currentState = s);
  }

  Iterable<ag_ui.Run> get runs => _runs;

  final Map<String, ToolCallReceptionBuffer> _toolCallReceptions = {};
  final _toolRegistry = ToolCallRegistry();

  /// Stream of messages (user and assistant).
  Stream<ag_ui.Message> get messageStream => _messagesController.stream;

  /// Stream of state updates.
  Stream<ag_ui.State> get stateStream => _statesController.stream;

  /// Stream of all AG-UI events (for UI updates).
  Stream<ag_ui.BaseEvent> get stepsStream => _stepsController.stream;

  /// List of registered tools.
  List<ag_ui.Tool> get tools => List.unmodifiable(_tools);

  /// Add a tool dynamically.
  void addTool(ag_ui.Tool tool, ToolExecutor executor) {
    _tools.add(tool);
    _toolExecutors[tool.name] = executor;
  }

  /// Remove a tool.
  void removeTool(String toolName) {
    _tools.removeWhere((t) => t.name == toolName);
    _toolExecutors.remove(toolName);
  }

  /// Safely add to steps stream (checks if disposed).
  void _addStep(ag_ui.BaseEvent event) {
    if (!_disposed) _stepsController.add(event);
  }

  /// Safely add to messages stream (checks if disposed).
  void _addMessage(ag_ui.Message message) {
    if (!_disposed) _messagesController.add(message);
  }

  /// Safely add to states stream (checks if disposed).
  void _addState(ag_ui.State state) {
    if (!_disposed) _statesController.add(state);
  }

  /// Start a run and process events.
  ///
  /// Returns list of tool messages if client tools were executed
  /// (caller should call again with these results).
  Future<List<ag_ui.ToolMessage>> startRun({
    required String endpoint,
    required String runId,
    List<ag_ui.Message>? messages,
    dynamic state,
  }) async {
    // Check if disposed before starting
    if (_disposed) {
      debugPrint('Thread: startRun called on disposed thread, ignoring');
      return [];
    }

    final run = ag_ui.Run(threadId: id, runId: runId);
    _runs.add(run);

    // Add any new messages to history
    messageHistory.addAll(messages ?? []);
    (messages ?? []).forEach(_addMessage);

    final agentInput = ag_ui.SimpleRunAgentInput(
      threadId: id,
      runId: runId,
      messages: messageHistory,
      state: state,
      tools: _tools,
    );

    try {
      await for (final event in client.runAgent(endpoint, agentInput)) {
        // Check if disposed during streaming
        if (_disposed) {
          debugPrint('Thread: disposed during event stream, stopping');
          break;
        }
        _addStep(event);

        switch (event) {
          case ag_ui.TextMessageChunkEvent(
            messageId: final msgId,
            delta: final text,
          ):
            final message = ag_ui.AssistantMessage(id: msgId, content: text);
            messageHistory.add(message);
            _addMessage(message);

          case ag_ui.TextMessageStartEvent(messageId: final msgId):
            _textBuffers[msgId] = TextMessageBuffer(msgId);

          case ag_ui.TextMessageContentEvent(
            messageId: final msgId,
            delta: final text,
          ):
            _textBuffers[msgId]?.add(msgId, text);

          case ag_ui.TextMessageEndEvent(messageId: final msgId):
            final buffer = _textBuffers.remove(msgId);
            final message = ag_ui.AssistantMessage(
              id: msgId,
              content: buffer?.content ?? '',
            );
            messageHistory.add(message);
            _addMessage(message);

          case ag_ui.StepStartedEvent():
            // Already added to stepsController above
            break;

          case ag_ui.StepFinishedEvent():
            // Already added to stepsController above
            break;

          case ag_ui.ToolCallStartEvent(
            toolCallId: final id,
            toolCallName: final name,
          ):
            _toolCallReceptions[id] = ToolCallReceptionBuffer(id, name);

          case ag_ui.ToolCallArgsEvent(
            toolCallId: final id,
            delta: final delta,
          ):
            _toolCallReceptions[id]?.appendArgs(delta);

          case ag_ui.ToolCallEndEvent(toolCallId: final id):
            final receivedToolCall = _toolCallReceptions.remove(id);

            if (receivedToolCall == null) break;

            messageHistory.add(receivedToolCall.message);

            final toolCall = receivedToolCall.toolCall;
            final isClientTool = _tools.any(
              (t) => t.name == toolCall.function.name,
            );
            if (isClientTool) {
              _toolRegistry.register(toolCall);
            }

          case ag_ui.ToolCallResultEvent(
            messageId: final msgId,
            toolCallId: final id,
            content: final content,
          ):
            final result = ag_ui.ToolMessage(
              id: msgId,
              toolCallId: id,
              content: content,
            );

            messageHistory.add(result);
            _toolRegistry.markCompleted(id, result);

          case ag_ui.StateSnapshotEvent(snapshot: final snapshot):
            _addState(snapshot);

          case ag_ui.StateDeltaEvent(delta: final deltas):
            // Simple merge for now (full JSON patch would require json_patch package)
            if (currentState is Map<String, dynamic>) {
              final current = currentState as Map<String, dynamic>;
              for (final delta in deltas) {
                if (delta is Map<String, dynamic>) {
                  current.addAll(delta);
                }
              }
              _addState(current);
            }

          case ag_ui.ActivitySnapshotEvent():
            // Activity snapshot - already forwarded to stepsStream above
            // Processing handled by UI layer
            break;

          // Thinking events - forwarded to stepsStream, handled by UI layer
          case ag_ui.ThinkingStartEvent():
          case ag_ui.ThinkingContentEvent():
          case ag_ui.ThinkingEndEvent():
          case ag_ui.ThinkingTextMessageStartEvent():
          case ag_ui.ThinkingTextMessageContentEvent():
          case ag_ui.ThinkingTextMessageEndEvent():
            break;

          // Run lifecycle events - forwarded to stepsStream
          case ag_ui.RunStartedEvent():
          case ag_ui.RunFinishedEvent():
            break;

          case ag_ui.RunErrorEvent(
            message: final errorMessage,
            code: final errorCode,
          ):
            final message = ag_ui.AssistantMessage(
              id: 'run-event-error-${event.timestamp ?? DateTime.now()}',
              content:
                  'Error${errorCode != null ? ' (Code $errorCode)' : ''}: $errorMessage',
            );
            messageHistory.add(message);
            _addMessage(message);

          default:
            debugPrint("Thread: Ignored event ${event.runtimeType}");
        }
      }
    } catch (e) {
      // Handle decoding errors from ag_ui package gracefully
      // This can happen when server sends event types the package doesn't recognize
      debugPrint('Thread: Error processing events: $e');

      final errorStr = e.toString();
      if (errorStr.contains('DecodingError') ||
          errorStr.contains('Invalid event type')) {
        // Try to get more details about what failed
        debugPrint('Thread: ===== DECODING ERROR DETAILS =====');

        // Check if it's a DecodingError with actualValue
        if (e is ag_ui.DecodingError) {
          final decodingError = e;
          debugPrint('Thread: Field: ${decodingError.field}');
          debugPrint('Thread: Expected: ${decodingError.expectedType}');
          debugPrint('Thread: Actual value: ${decodingError.actualValue}');
          if (decodingError.cause != null) {
            debugPrint('Thread: Cause: ${decodingError.cause}');
          }
        }

        // Also check for "Invalid event type: X" pattern in cause chain
        final typeMatch = RegExp(
          r'Invalid event type:\s*(\S+)',
        ).firstMatch(errorStr);
        if (typeMatch != null) {
          debugPrint(
            'Thread: Unknown event type from server: ${typeMatch.group(1)}',
          );
        }

        debugPrint('Thread: ===================================');
        debugPrint(
          'Thread: Ignoring decoding error - continuing with partial results',
        );
      } else {
        rethrow;
      }
    }

    // Execute any pending client tools
    final pendingToolCalls = _toolRegistry.pendingCalls;
    if (pendingToolCalls.isEmpty) {
      return [];
    }

    final results = await _executeClientTools(pendingToolCalls.toList());
    for (final result in results) {
      _toolRegistry.markCompleted(result.toolCallId, result);
    }
    return results;
  }

  Future<List<ag_ui.ToolMessage>> _executeClientTools(
    List<ag_ui.ToolCall> toolCalls,
  ) async {
    final results = await Future.wait(
      toolCalls.map((toolCall) => _executeClientTool(toolCall)),
    );

    final toolMessages = <ag_ui.ToolMessage>[];
    for (int i = 0; i < results.length; i++) {
      final toolCallId = toolCalls[i].id;
      final result = results[i];

      toolMessages.add(
        ag_ui.ToolMessage(
          id: 'msg-$toolCallId',
          toolCallId: toolCallId,
          content: result,
        ),
      );
    }

    return toolMessages;
  }

  Future<String> _executeClientTool(ag_ui.ToolCall toolCall) async {
    debugPrint(
      'Thread: _executeClientTool called for ${toolCall.function.name}',
    );
    final executor = _toolExecutors[toolCall.function.name];

    if (executor == null) {
      debugPrint('Thread: No executor found for ${toolCall.function.name}');
      throw StateError(
        'No executor registered for client tool: ${toolCall.function.name}',
      );
    }

    try {
      debugPrint('Thread: Calling executor for ${toolCall.function.name}...');
      final result = await executor(toolCall);
      debugPrint(
        'Thread: Executor returned: ${result.substring(0, result.length.clamp(0, 100))}...',
      );
      return result;
    } catch (e) {
      debugPrint('Thread: Executor threw error: $e');
      return 'ERROR: ${e.toString()}';
    }
  }

  /// Send tool results and continue the run.
  Future<List<ag_ui.ToolMessage>> sendToolResults({
    required String endpoint,
    required String runId,
    required List<ag_ui.ToolMessage> toolMessages,
  }) async {
    return startRun(endpoint: endpoint, runId: runId, messages: toolMessages);
  }

  /// Clear all state for a new conversation.
  void reset() {
    messageHistory.clear();
    _runs.clear();
    _toolCallReceptions.clear();
    _toolRegistry.clear();
    _textBuffers.clear();
    currentState = null;
  }

  void dispose() {
    _disposed = true;
    _messagesController.close();
    _statesController.close();
    _stepsController.close();
  }
}
