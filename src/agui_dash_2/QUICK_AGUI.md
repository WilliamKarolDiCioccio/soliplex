# Quick AG-UI Architecture

This document describes the `quick_agui` infrastructure used in `agui_dash_2` for AG-UI protocol communication.

## Overview

The `quick_agui` module provides a clean separation of concerns for AG-UI client communication:

```
┌─────────────────────────────────────────────────────────────┐
│                      AgUiService                            │
│  - Manages configuration (baseUrl, roomId)                  │
│  - Creates threads and runs via HTTP                        │
│  - Registers tools with Thread                              │
│  - Handles tool result loop                                 │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                        Thread                               │
│  - Maintains message history                                │
│  - Processes SSE events from ag_ui.AgUiClient               │
│  - Manages tool call registry                               │
│  - Executes client tools via pluggable executors            │
│  - Exposes reactive streams for UI                          │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
┌───────────┐  ┌───────────┐  ┌───────────┐
│  Message  │  │   State   │  │   Steps   │
│  Stream   │  │  Stream   │  │  Stream   │
└───────────┘  └───────────┘  └───────────┘
```

## Core Components

### Thread (`lib/infrastructure/quick_agui/thread.dart`)

The Thread class is the core abstraction for an AG-UI conversation.

**Responsibilities:**
- Maintains `messageHistory` list of all messages in the conversation
- Processes SSE events from `ag_ui.AgUiClient.runAgent()`
- Tracks pending and completed tool calls via `ToolCallRegistry`
- Auto-executes client-side tools using pluggable `ToolExecutor` callbacks
- Exposes broadcast streams for reactive UI updates

**Key Properties:**
```dart
final String id;                           // Thread ID from server
final ag_ui.AgUiClient client;             // AG-UI SSE client
final List<ag_ui.Message> messageHistory;  // All messages
ag_ui.State? currentState;                 // Latest state snapshot
```

**Streams (all broadcast):**
```dart
Stream<ag_ui.Message> messageStream;   // User and assistant messages
Stream<ag_ui.State> stateStream;       // State snapshots/deltas
Stream<ag_ui.BaseEvent> stepsStream;   // All AG-UI events (for UI)
```

**Tool Registration:**
```dart
void addTool(ag_ui.Tool tool, ToolExecutor executor);
void removeTool(String toolName);
```

**Run Lifecycle:**
```dart
// Start a run, returns tool results that need to be sent back
Future<List<ag_ui.ToolMessage>> startRun({
  required String endpoint,
  required String runId,
  List<ag_ui.Message>? messages,
  dynamic state,
});

// Send tool results and continue
Future<List<ag_ui.ToolMessage>> sendToolResults({
  required String endpoint,
  required String runId,
  required List<ag_ui.ToolMessage> toolMessages,
});
```

### Helper Classes

#### TextMessageBuffer (`text_message_buffer.dart`)

Accumulates streamed text content by messageId.

```dart
class TextMessageBuffer {
  final String messageId;
  void add(String id, String content);  // Validates messageId matches
  String get content;                    // Returns accumulated text
}
```

Used to buffer `TextMessageContentEvent` deltas until `TextMessageEndEvent`.

#### ToolCallReceptionBuffer (`tool_call_reception_buffer.dart`)

Buffers streamed tool call arguments.

```dart
class ToolCallReceptionBuffer {
  final String id;
  final String name;
  void appendArgs(String delta);
  String get args;                    // Raw JSON string
  ag_ui.ToolCall get toolCall;        // Parsed ToolCall object
  ag_ui.AssistantMessage get message; // Wrapped in AssistantMessage
}
```

Used to buffer `ToolCallArgsEvent` deltas until `ToolCallEndEvent`.

#### ToolCallRegistry (`tool_call_registry.dart`)

Tracks pending and completed tool calls.

```dart
class ToolCallRegistry {
  void register(ToolCall call);
  void markCompleted(String toolCallId, ToolMessage message);
  Iterable<ToolCall> get pendingCalls;
  Iterable<ToolMessage> get results;
  void clear();
}
```

Separates tool calls into:
- **Pending**: Client tools that need execution
- **Completed**: Tools with results (either from server or client execution)

## Event Processing Flow

### 1. Text Message Events

```
TextMessageStartEvent → create TextMessageBuffer
TextMessageContentEvent → buffer.add(delta)
TextMessageEndEvent → create AssistantMessage, add to history
```

### 2. Tool Call Events

```
ToolCallStartEvent → create ToolCallReceptionBuffer
ToolCallArgsEvent → buffer.appendArgs(delta)
ToolCallEndEvent →
  - Add AssistantMessage with tool_calls to history
  - If client tool: register in ToolCallRegistry as pending
```

### 3. Tool Execution

After SSE stream ends, Thread checks for pending client tools:

```dart
final pendingToolCalls = _toolRegistry.pendingCalls;
if (pendingToolCalls.isNotEmpty) {
  final results = await _executeClientTools(pendingToolCalls.toList());
  return results;  // Caller should send these back to server
}
```

### 4. State Events

```
StateSnapshotEvent → replace currentState, emit on stateStream
StateDeltaEvent → merge delta into currentState (simplified)
```

## AgUiService Integration

The `AgUiService` wraps Thread and handles:

1. **Configuration**: baseUrl, roomId, headers
2. **Thread/Run Creation**: HTTP POST to create thread and runs
3. **Tool Registration**: Registers `LocalToolsService` tools with Thread
4. **Tool Result Loop**: Sends tool results back until no more pending

### chat() Method

Main entry point for sending messages:

```dart
Future<void> chat(
  String userMessage, {
  required LocalToolsService localToolsService,
  required void Function(ag_ui.BaseEvent event) onEvent,
}) async {
  // 1. Create thread if needed (POST to /rooms/{room}/agui)
  // 2. Register tools with thread
  // 3. Subscribe to stepsStream for UI updates
  // 4. Call thread.startRun()
  // 5. Loop: while toolResults.isNotEmpty, create new run and send results
}
```

## Tool Executor Pattern

Tools are registered with a callback that receives the `ToolCall` and returns a JSON string result:

```dart
typedef ToolExecutor = Future<String> Function(ag_ui.ToolCall call);

_thread.addTool(agTool, (call) async {
  final args = jsonDecode(call.function.arguments);
  final result = await localToolsService.executeTool(call.id, call.function.name, args);
  return jsonEncode(result.success ? result.result : {'error': result.error});
});
```

## Important Design Decisions

### 1. Mutable Lists for Tools

Thread constructor creates mutable copies of tool lists:

```dart
Thread({...})
  : _tools = tools != null ? List.from(tools) : <ag_ui.Tool>[],
    _toolExecutors = toolExecutors != null ? Map.from(toolExecutors) : {};
```

**Why**: Default `const []` parameters are unmodifiable; `addTool()` would fail.

### 2. Broadcast Streams

All streams are broadcast (`StreamController.broadcast()`):

**Why**: Multiple listeners may need the same events (UI components, logging, etc.)

### 3. Tool Result Loop in Caller

`startRun()` returns pending tool results rather than looping internally:

**Why**:
- Caller controls when/if to continue
- Each continuation needs a new run ID (HTTP POST)
- Allows caller to update UI between iterations

### 4. Client Tool Detection

```dart
final isClientTool = _tools.any((t) => t.name == toolCall.function.name);
if (isClientTool) {
  _toolRegistry.register(toolCall);
}
```

**Why**: Only tools registered with Thread are client tools. Server tools have results sent via `ToolCallResultEvent`.

## Concurrency Considerations

### Location Permission Lock

The `LocalToolsService` uses a lock for location permission requests:

```dart
bool _locationPermissionInProgress = false;
Completer<LocationPermission>? _permissionCompleter;
```

**Why**: `Geolocator.requestPermission()` throws if called while another request is in progress. Multiple tool calls can happen concurrently.

### Widget Disposal in Async Streams

When processing events in Flutter widgets:

```dart
// WRONG - ref may be invalid after await
await for (final event in events) {
  ref.read(someProvider.notifier).doSomething();  // May throw!
}

// CORRECT - capture before async loop
final notifier = ref.read(someProvider.notifier);
await for (final event in events) {
  if (!mounted) break;
  notifier.doSomething();
}
```

**Why**: Widget may be disposed during async iteration; `ref` becomes invalid.

## State Delta Handling

Current implementation uses simple merge:

```dart
case ag_ui.StateDeltaEvent(delta: final deltas):
  if (currentState is Map<String, dynamic>) {
    final current = currentState as Map<String, dynamic>;
    for (final delta in deltas) {
      if (delta is Map<String, dynamic>) {
        current.addAll(delta);
      }
    }
  }
```

**Limitation**: This doesn't handle JSON Patch operations (add, remove, replace, move, copy, test). For full compliance, use the `json_patch` package.

## File Structure

```
lib/infrastructure/quick_agui/
├── thread.dart                    # Core Thread class
├── text_message_buffer.dart       # Text streaming buffer
├── tool_call_reception_buffer.dart # Tool args streaming buffer
└── tool_call_registry.dart        # Pending/completed tool tracking
```

## Usage Example

```dart
// Create client and thread
final client = ag_ui.AgUiClient(
  config: ag_ui.AgUiClientConfig(baseUrl: 'http://localhost:8000/api/v1'),
);

final thread = Thread(id: threadId, client: client);

// Register tools
thread.addTool(
  ag_ui.Tool(name: 'get_location', description: '...', parameters: {...}),
  (call) async => '{"lat": 37.7749, "lng": -122.4194}',
);

// Listen to events
thread.stepsStream.listen((event) => print('Event: $event'));
thread.messageStream.listen((msg) => print('Message: $msg'));

// Start conversation
var toolResults = await thread.startRun(
  endpoint: 'rooms/myroom/agui/$threadId/$runId',
  runId: runId,
  messages: [ag_ui.UserMessage(id: 'msg1', content: 'Hello')],
);

// Handle tool results
while (toolResults.isNotEmpty) {
  final newRunId = await createRun(threadId);
  toolResults = await thread.sendToolResults(
    endpoint: 'rooms/myroom/agui/$threadId/$newRunId',
    runId: newRunId,
    toolMessages: toolResults,
  );
}
```
