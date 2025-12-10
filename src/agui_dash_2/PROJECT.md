# PROJECT.md - AG-UI Implementation Action Plan

## Project Overview

Implementation of an Agentic Generative User Interface (AG-UI) chat application using Flutter, integrating Dash Chat 2 for conversational UX and Remote Flutter Widgets (RFW) for dynamic, secure UI rendering.

**Architecture Summary:**
- **AG-UI Protocol**: Standardized communication between AI agent and Flutter client
- **Dash Chat 2**: Manages conversation flow, message history, and user input
- **RFW (Remote Flutter Widgets)**: Secure, sandboxed rendering of agent-generated UI

---

## Current Status (Session 5) - GenUI Rendering Complete

### Completed:
- [x] Phase 1: Project foundation with Flutter, Riverpod, Dash Chat 2, RFW
- [x] Added `ag_ui` package (v0.1.0) for AG-UI protocol types
- [x] Created `RfwService` singleton for RFW runtime management
- [x] Created `ChatService` with message state management
- [x] Created `AgUiService` with correct 2-step endpoint flow
- [x] Integrated chat screen with AG-UI service
- [x] Build compiles successfully for macOS
- [x] **Created standalone Dart CLI client** (`bin/agui_client.dart`)
- [x] **Verified end-to-end AG-UI flow works** - "tell me a computer joke" returns response!
- [x] **Fixed payload format** - discovered `forwardedProps` is required by server
- [x] **SSE streaming and event parsing verified working**
- [x] **Phase 2: RFW Pipeline Implementation** (Session 3)
  - [x] Isolate-based `RfwDecoder` with LRU caching
  - [x] Chart widgets: `LineChart`, `BarChart`, `PieChart` (fl_chart)
  - [x] Media widgets: `SvgImage`, `NetworkImage` (with SSRF protection)
  - [x] `DynamicContentManager` for per-message state management
- [x] **Local Tool Calling** (Session 4) - WORKING!
  - [x] Room selector dropdown - fetches rooms from `/api/v1/rooms`
  - [x] Local tools service framework with tool registration
  - [x] `get_my_location` GPS tool using geolocator package
  - [x] Message history tracking for tool result submission
  - [x] Full round-trip: user message -> tool call -> local execution -> result sent back -> agent continues

### Key Findings (Session 2):
1. Server uses **2-step flow** (not 3-step): Thread creation auto-creates initial run
2. Payload **must include `forwardedProps: {}`** or server returns 500
3. Run ID is extracted from `runs` map in thread response, not separate endpoint
4. Event types observed: `RUN_STARTED`, `THINKING_*`, `TOOL_CALL_*`, `TEXT_MESSAGE_*`, `RUN_FINISHED`

### Session 3 Additions:
- `RfwDecoder` - Isolate-based binary/text decoder with FNV-1a hash caching
- `DynamicContentManager` - Per-message content lifecycle with snapshot/delta support
- 5 new chart/media widgets registered in local library
- Build verified with `--no-tree-shake-icons` flag (required for RFW dynamic icons)

### Session 4 Additions:
- **Room selector dropdown** - Fetches available rooms from `/api/v1/rooms`
- **Local Tools Service** - Client-side tool execution framework
- **`get_my_location` tool** - GPS location tool using geolocator package
- **Message history tracking** - Required for tool result submission (AG-UI protocol)
- **Fixed Riverpod provider initialization** - Deferred configuration via `Future.microtask`
- **AG-UI message format** - Uses camelCase (`toolCalls`, `toolCallId`) per protocol spec

### Session 5 Additions - GenUI Rendering:
- **`genui_render` tool** - Client-side tool for rendering dynamic RFW widgets
- **Tool registration** - Both `get_my_location` and `genui_render` registered in LocalToolsService
- **Special tool handling** - `genui_render` is client-only (no result sent back to server)
- **RFW widget rendering** - Agent can now send dynamic UI widgets that render in chat
- **Button events working** - RFW `onEvent` callbacks fire when user interacts with widgets
- **Fixed typing indicator** - Clears after GenUI rendering completes
- **Fixed macOS permission race** - Retry mechanism for freshly granted location permissions
- **Fixed DynamicContent data access** - Data stored at root level so RFW `data.fieldName` works correctly

### Test Results:
```
$ dart run bin/agui_client.dart
=== AG-UI CLI Client Test ===
Step 1: Creating thread (with initial run)...
  Thread ID: eeb04664-77aa-42c7-be0d-13b789377720
  Run ID: 71281c58-1027-4247-89d3-3de300f09ca1
Step 2: Sending message and streaming response...
  [RUN_STARTED] runId=71281c58-1027-4247-89d3-3de300f09ca1
  [TOOL_CALL_START] toolCallId=call_obayjx7f name=joke_factory
  [TEXT_MESSAGE_START] messageId=fec6d321-2a0e-4dda-a364-6f38f3b7e659
  Here's a computer joke for you: "Why did the computer keep taking coffee breaks?..."
  [TEXT_MESSAGE_END]
  [RUN_FINISHED]
Test completed successfully!
```

### Local Tool Calling - WORKING!
The client supports local (client-side) tool execution framework. When the server calls a local tool:
1. Tool definition is sent to server with the message request
2. Server calls the tool, client intercepts `TOOL_CALL_*` events
3. Client executes the tool locally (e.g., GPS via geolocator)
4. Assistant message with tool call is recorded in message history
5. Result is sent back to server via `sendToolResult()` with full message history
6. Server continues processing with the tool result

**Available Local Tools:**
- `get_my_location` - Returns GPS coordinates (lat, lng, accuracy, altitude, speed, heading, timestamp)

**To test:** Select the `mcptest` room and ask the agent to get your location.

### Key Technical Details (Session 4):
1. **Message History Format** - AG-UI protocol requires full conversation history when sending tool results:
   ```json
   [
     {"role": "user", "id": "...", "content": "where am i?"},
     {"role": "assistant", "id": "...", "content": "", "toolCalls": [...]},
     {"role": "tool", "id": "...", "toolCallId": "...", "content": "{...}"}
   ]
   ```
2. **camelCase Keys** - AG-UI Python models use `alias_generator=to_camel`, so JSON keys must be camelCase
3. **Tool Call ID Matching** - Server validates that `toolCallId` in ToolMessage matches an AssistantMessage's tool call

### Remaining Work:
1. ~~**GenUI widget rendering** - Demo RFW widgets from agent responses~~ ✅ COMPLETE
2. **Phase 5: Security** - Sandboxing, validation, error handling
3. **Human-in-the-loop** - Send RFW `onEvent` callbacks back to agent (events fire, need server integration)

### Next Phase: Advanced GenUI Widgets
Create more complex widgets: forms, charts, data cards.

---

## GenUI Rendering with RFW

> **📄 Full Documentation: See [GENUI-RFW.md](./GENUI-RFW.md)**

The `genui_render` tool allows the AI agent to render dynamic UI widgets in the chat using Remote Flutter Widgets (RFW).

### Quick Summary

| Tool | Registered | Sent to Server | Result Sent Back | Purpose |
|------|------------|----------------|------------------|---------|
| `get_my_location` | LocalToolsService | ✅ Yes | ✅ Yes | Device capabilities |
| `genui_render` | LocalToolsService | ✅ Yes | ❌ No | UI rendering only |

### Key Points

1. **RFW is NOT Dart** - Uses similar syntax but with critical differences
2. **Enums are strings** - `"min"` not `MainAxisSize.min`
3. **Padding is arrays** - `[16.0, 16.0, 16.0, 16.0]` not `EdgeInsets.all(16.0)`
4. **Colors are hex** - `0xFF2196F3` not `Colors.blue`
5. **Events fire on client** - Currently logged; future: send to agent

See [GENUI-RFW.md](./GENUI-RFW.md) for:
- Complete syntax reference
- Dart vs RFW comparison
- 3 examples of increasing complexity
- System prompt template for AI agents
- Troubleshooting guide
- Color reference

---

## Critical Design Decision: SSE over WebSocket

**IMPORTANT**: This implementation uses **Server-Sent Events (SSE)** for agent communication, NOT WebSockets.

### Rationale:
1. **AG-UI Protocol Standard**: The official AG-UI protocol uses SSE for streaming events from agent to client
2. **Official SDK**: The `ag_ui` Dart package provides production-ready SSE streaming with backpressure handling
3. **Simplicity**: SSE is unidirectional (server→client), which matches the AG-UI event model perfectly
4. **HTTP-native**: SSE works over standard HTTP, simplifying deployment (no WebSocket upgrade needed)
5. **Auto-reconnection**: SSE has built-in reconnection semantics

---

## Server Endpoint Flow (2-Step)

**UPDATED**: The AG-UI server uses a 2-step flow. Thread creation auto-creates initial run.

### Step 1: Create Thread (with initial run)
```
POST /api/v1/rooms/{room_id}/agui
Body: {} (empty JSON, optional metadata)
Response: {
  "thread_id": "uuid",
  "runs": {
    "run_id_here": { ... }  // Initial run auto-created!
  }
}
```

### Step 2: Execute Run (SSE Stream)
```
POST /api/v1/rooms/{room_id}/agui/{thread_id}/{run_id}
Content-Type: application/json
Accept: text/event-stream
Body: {
  "thread_id": "...",
  "run_id": "...",
  "messages": [{"role": "user", "id": "...", "content": "..."}],
  "tools": [],
  "context": [],
  "state": {},
  "forwardedProps": {}  // REQUIRED!
}
Response: SSE stream of AG-UI events
```

### For Subsequent Messages (same thread):
```
POST /api/v1/rooms/{room_id}/agui/{thread_id}
Body: {} (creates new run)
Response: { "run_id": "new_uuid", ... }
```
Then execute as Step 2.

### Example Working Interaction:
```
POST /api/v1/rooms/joker/agui -> 200 OK (thread + initial run)
POST /api/v1/rooms/joker/agui/{thread}/{run} -> 200 OK (SSE stream)
  [RUN_STARTED]
  [TOOL_CALL_START] joke_factory
  [TOOL_CALL_ARGS] {"count":1,"topic":"computer"}
  [TOOL_CALL_END]
  [TEXT_MESSAGE_START]
  [TEXT_MESSAGE_CONTENT] Here's a computer joke...
  [TEXT_MESSAGE_END]
  [RUN_FINISHED]
```

---

## Phase 1: Project Foundation & Core Infrastructure ✅ COMPLETE

### 1.1 Project Setup
- [x] Initialize Flutter project structure
- [x] Configure `pubspec.yaml` with required dependencies:
  - `rfw` (Remote Flutter Widgets)
  - `dash_chat_2` (Chat UI)
  - `http` (HTTP/SSE communication - not WebSocket)
  - `flutter_riverpod` (state management/DI)
  - `fl_chart` (charting support)
  - `flutter_svg` (SVG rendering)
  - `ag_ui` (AG-UI protocol types)
- [x] Set up directory structure:
  ```
  lib/
  ├── main.dart
  ├── core/
  │   ├── services/
  │   ├── models/
  │   └── utils/
  ├── features/
  │   ├── chat/
  │   └── rfw/
  └── widgets/
      └── local/
  ```

### 1.2 RFW Runtime Service
- [x] Create `RfwService` as a singleton/long-lived scoped provider
- [x] Initialize `Runtime` object with proper lifecycle management
- [x] Register core widget libraries on initialization
- [x] Implement `LocalWidgetLibrary` registration mechanism
- [x] Create `DynamicContent` instance management per-message
- [x] Handle Runtime destruction gracefully (cache preservation)

---

## Phase 2: RFW Pipeline Implementation ✅ COMPLETE

### 2.1 Binary Decoding Pipeline
- [x] Implement `decodeLibraryBlob` wrapper with comprehensive error handling
- [x] Create isolate-based decoder (`RfwDecoder`) for non-blocking performance
- [x] Implement compute pool for parallel decoding of multiple payloads
- [x] Add support for both binary (`.rfw`) and text (`.rfwtxt`) formats
- [x] Prefer binary format in production for performance

### 2.2 Local Widget Library
- [x] Create base `LocalWidgetBuilder` interface/abstract class
- [x] Implement chart wrappers (fl_chart integration):
  - [x] `LocalLineChart` - maps `dataPoints` array to `FlSpot` objects
  - [x] `LocalBarChart` - maps category/value pairs to `BarChartGroupData`
  - [x] `LocalPieChart` - maps segments to `PieChartSectionData`
- [x] Implement media wrappers:
  - [x] `LocalSvgImage` - wraps `flutter_svg` with `asset_name` or `url` mapping
  - [x] `LocalNetworkImage` - with domain whitelist validation (SSRF prevention)
  - [ ] `LocalLottieAnimation` - wraps `lottie` package with `url` mapping
- [ ] Implement map wrapper (deferred - requires Google Maps API key):
  - [ ] `LocalGoogleMap` - maps `lat`, `lng`, `markers` list to GoogleMap widget
  - [ ] Handle `GoogleMapController` lifecycle
- [x] Register all local widgets with RFW Runtime under `['local']` LibraryName

### 2.3 DynamicContent Management
- [x] Create `DynamicContentManager` class for per-message state
- [x] Implement reactive data binding between AG-UI STATE_UPDATE events and DynamicContent
- [x] Support partial updates (data-only updates without full widget tree rebuild)
- [x] Create stream/listener infrastructure for real-time data updates
- [x] Implement dirty checking to minimize unnecessary rebuilds

---

## Phase 3: Dash Chat 2 Integration ✅ MOSTLY COMPLETE

### 3.1 Chat Infrastructure
- [x] Create `ChatService` with message management
- [x] Define `ChatUser` models (user, agent, system)
- [x] Implement message persistence (in-memory initially)
- [x] Set up message ordering by timestamp

### 3.2 Custom Message Protocol
- [x] Extend `ChatMessage.customProperties` with GenUI metadata
- [x] Create `GenUiMessage` model class (in `chat_models.dart`)
- [x] Support identifying GenUI messages via `MessageType.genUi`

### 3.3 Custom Message Builder
- [x] Implement `messageBuilder` function for DashChat widget
- [x] Create message type router (text vs GenUI)
- [x] Create `RfwMessageWidget` that renders RemoteWidget within chat bubble
- [x] Handle layout constraints with ConstrainedBox
- [x] Style GenUI bubbles distinctly from text messages
- [x] Handle loading states while RFW payload is being received

### 3.4 Event Bridging (Human-in-the-Loop)
- [x] Wire RFW `onEvent` callbacks to AG-UI protocol layer (basic)
- [ ] Create event serialization for user interactions
- [ ] Implement bidirectional event flow (user action → agent response)
- [ ] Support quick replies integration between Dash Chat 2 and RFW events

---

## Phase 4: AG-UI Protocol Implementation ✅ CORE COMPLETE

### 4.1 SSE Connection Layer
- [x] Create `AgUiService` with custom HTTP handling (not `ag_ui` AgUiClient)
- [x] Configure with Base URL and Room ID management
- [x] Implement SSE stream handling with correct 2-step flow
- [x] **Fixed payload format** - includes required `forwardedProps`
- [ ] Handle connection errors and automatic retry

### 4.2 Event Stream Router
- [x] Use `BaseEvent.fromJson()` from `ag_ui` package for typed events
- [x] Implement event type router handling core AG-UI events:
  - [x] `RUN_STARTED` - Log run start
  - [x] `TEXT_MESSAGE_START` - Initialize new text message
  - [x] `TEXT_MESSAGE_CONTENT` - Append streamed text chunks
  - [x] `TEXT_MESSAGE_END` - Finalize text message
  - [x] `TOOL_CALL_START` - Prepare loading placeholder in chat
  - [x] `TOOL_CALL_ARGS` - Buffer args chunks
  - [x] `TOOL_CALL_END` - Finalize tool call
  - [x] `RUN_FINISHED` - Log run completion
  - [x] `RUN_ERROR` - Display error message
  - [ ] `STATE_SNAPSHOT` / `STATE_DELTA` - Apply DynamicContent updates
- [x] Create event parsing and validation layer
- [x] Handle unknown/future event types gracefully (logged as unhandled)

### 4.3 Message Assembly
- [x] Implement streaming text message assembly
- [x] Implement tool call args buffering
- [x] Create message finalization logic (commit to chat history)
- [ ] Handle mixed content (text + GenUI in same agent response)
- [ ] Support message editing/updates from agent corrections

### 4.4 Client-to-Agent Communication
- [x] User messages sent via `sendMessage()` in correct format
- [ ] Define event format for user actions (human-in-the-loop)
- [ ] Implement send queue with retry logic
- [ ] Handle acknowledgment from agent
- [ ] Support typed user input from RFW forms

---

## Phase 5: Security Implementation

### 5.1 Sandboxing Enforcement
- [ ] Validate all RFW payloads before rendering
- [ ] Implement widget tree depth limiter:
  - Define max nesting threshold (e.g., 50 levels)
  - Reject trees exceeding threshold during decode phase
  - Log rejected payloads for monitoring
- [ ] Create whitelist of allowed widget types
- [ ] Prevent arbitrary Dart code execution (RFW design guarantee)

### 5.2 Network Security
- [ ] Implement domain whitelist for `LocalNetworkImage`:
  - Only allow images from approved CDN domains
  - Proxy through secure content delivery network if needed
- [ ] Sanitize all URL inputs in local widgets
- [ ] Prevent SSRF attacks via internal IP detection
- [ ] Log suspicious payloads for security monitoring

### 5.3 Input Validation
- [ ] Validate DynamicContent data types match expected schema
- [ ] Sanitize string inputs to prevent XSS in rendered content
- [ ] Implement size limits for payload buffers (prevent memory exhaustion)
- [ ] Validate numeric ranges for chart data points

### 5.4 Error Handling
- [ ] Display graceful fallback UI for invalid RFW payloads
- [ ] Never crash app due to malformed agent response
- [ ] Log errors with context for debugging

---

## Phase 6: Performance Optimization

### 6.1 Caching Layer
- [ ] Implement LRU cache for `RemoteWidgetLibrary` blobs
- [ ] Support library references by name (e.g., `import core_styles;`)
- [ ] Check cache before requesting from server
- [ ] Use `Runtime.update` to load cached libraries
- [ ] Implement cache eviction policy
- [ ] Add cache hit/miss metrics for monitoring

### 6.2 Concurrency & Isolates
- [ ] Move `decodeLibraryBlob` execution to separate Dart Isolate
- [ ] Implement compute pool for parallel decoding
- [ ] Ensure main UI thread never blocks on parsing
- [ ] Use `compute()` or custom isolate management
- [ ] Handle isolate errors gracefully

### 6.3 Efficient Updates
- [ ] Implement dirty checking for DynamicContent changes
- [ ] Support differential state updates (only changed fields)
- [ ] Minimize widget rebuilds on data changes
- [ ] Separate layout (sent once) from data (sent on updates)
- [ ] Profile and optimize hot paths

### 6.4 Network Optimization
- [ ] Use binary format (`.rfw`) over text (`.rfwtxt`) in production
- [ ] Compress large payloads if supported
- [ ] Implement request deduplication

---

## Phase 7: Advanced Components

### 7.1 Chart Integration (fl_chart)
- [ ] `LocalLineChart`:
  - Map `dataPoints: [{x, y}, ...]` to `FlSpot` list
  - Support `color`, `strokeWidth`, `fillColor` properties
  - Enable touch interactions via `onEvent`
- [ ] `LocalBarChart`:
  - Map `bars: [{label, value}, ...]` to `BarChartGroupData`
  - Support grouped and stacked configurations
- [ ] `LocalPieChart`:
  - Map `segments: [{value, color, title}, ...]` to sections
  - Support touch selection feedback
- [ ] Interactive features:
  - Tooltips on hover/tap
  - Tap handlers that emit events to agent

### 7.2 Form Support
- [ ] Create `FluxForm` local widget with schema-driven fields:
  ```dart
  FluxForm(
    schema: {
      'fields': [
        {'name': 'email', 'type': 'text', 'validation': {'regex': '...'} },
        {'name': 'quantity', 'type': 'number', 'validation': {'min': 1} },
      ]
    }
  )
  ```
- [ ] Implement client-side validation:
  - Regex patterns
  - Required field checking
  - Min/max for numbers
  - Custom validators
- [ ] Handle form state management locally (reduce latency)
- [ ] Emit validated form data on submission via `onEvent`
- [ ] Show inline validation errors
- [ ] Support form reset and pre-population

### 7.3 Map Support (google_maps_flutter)
- [ ] `LocalGoogleMap`:
  - Map `center: {lat, lng}` to camera position
  - Map `markers: [{lat, lng, title}, ...]` to Marker set
  - Support zoom level configuration
- [ ] Handle map controller lifecycle
- [ ] Implement marker tap events
- [ ] Handle location permissions appropriately

### 7.4 Media Support
- [ ] `LocalSvgImage`:
  - Support `asset_name` for bundled assets
  - Support `url` for network SVGs
- [ ] `LocalNetworkImage`:
  - Domain whitelist enforcement
  - Placeholder during loading
  - Error image fallback
- [ ] `LocalLottieAnimation`:
  - Map `url` to `Lottie.network` source
  - Support play/pause controls
  - Handle animation completion events

---

## Phase 8: Testing & Quality Assurance

### 8.1 Unit Tests
- [ ] `RfwService` tests:
  - Runtime initialization
  - Widget library registration
  - DynamicContent updates
- [ ] `AgUiService` tests:
  - Event routing correctness
  - Message assembly logic
  - Connection state management
- [ ] Security validation tests:
  - Depth limiter enforcement
  - Domain whitelist blocking
  - Invalid payload rejection
- [ ] Cache tests:
  - LRU eviction behavior
  - Cache hit/miss logic

### 8.2 Widget Tests
- [ ] Custom message builder routing tests
- [ ] `RfwMessageWidget` rendering tests
- [ ] Layout constraint enforcement tests
- [ ] Local widget wrapper tests (charts, forms, maps)
- [ ] Error state rendering tests

### 8.3 Integration Tests
- [ ] End-to-end chat flow with mock agent
- [ ] WebSocket reconnection scenarios
- [ ] Mixed message type rendering
- [ ] Form submission round-trip
- [ ] Chart interaction events

### 8.4 Performance Tests
- [ ] Measure 60fps maintenance with dynamic content
- [ ] Profile isolate-based decoding
- [ ] Benchmark cache performance
- [ ] Test with large widget trees
- [ ] Memory usage under sustained operation

### 8.5 Security Tests
- [ ] Attempt to render disallowed widgets
- [ ] Test depth limit enforcement with deep trees
- [ ] Test SSRF prevention with internal IPs
- [ ] Fuzz test payload parsing

---

## Key Files

| File Path | Purpose | Status |
|-----------|---------|--------|
| `bin/agui_client.dart` | Standalone Dart CLI for testing AG-UI endpoint | ✅ Created |
| `lib/main.dart` | App entry point with provider setup | ✅ Created |
| `lib/core/services/rfw_service.dart` | RFW Runtime management singleton | ✅ Created |
| `lib/core/services/agui_service.dart` | AG-UI SSE connection & event routing | ✅ Created |
| `lib/core/services/chat_service.dart` | Chat message state management | ✅ Created |
| `lib/core/models/agui_events.dart` | AG-UI event type definitions | ✅ Created |
| `lib/core/models/chat_models.dart` | ChatUser and related models | ✅ Created |
| `lib/core/utils/security_validator.dart` | Security validation utilities | ✅ Created |
| `lib/core/utils/lru_cache.dart` | LRU cache implementation | ✅ Created |
| `lib/features/chat/chat_screen.dart` | Main chat UI screen | ✅ Created |
| `lib/features/chat/widgets/rfw_message_widget.dart` | RFW renderer for chat | ✅ Created |
| `lib/features/chat/builders/message_builder.dart` | Custom Dash Chat message builder | ✅ Created |
| `lib/widgets/local/local_widget_library.dart` | Local widget registry | ✅ Created |
| `lib/core/utils/rfw_decoder.dart` | Isolate-based binary decoder | ✅ Created |
| `lib/core/services/dynamic_content_manager.dart` | Per-message DynamicContent lifecycle | ✅ Created |
| `lib/widgets/local/charts/local_line_chart.dart` | fl_chart LineChart wrapper | ✅ Created |
| `lib/widgets/local/charts/local_bar_chart.dart` | fl_chart BarChart wrapper | ✅ Created |
| `lib/widgets/local/charts/local_pie_chart.dart` | fl_chart PieChart wrapper | ✅ Created |
| `lib/widgets/local/media/local_svg_image.dart` | SVG wrapper with security | ✅ Created |
| `lib/widgets/local/media/local_network_image.dart` | Secure network image (SSRF prevention) | ✅ Created |
| `lib/core/services/rooms_service.dart` | Room list fetching and selection | ✅ Created |
| `lib/core/services/local_tools_service.dart` | Client-side local tool execution | ✅ Created |
| `lib/widgets/local/forms/flux_form.dart` | Schema-driven form widget | 📋 TODO |
| `lib/widgets/local/media/local_lottie.dart` | Lottie animation wrapper | 📋 TODO |
| `lib/widgets/local/maps/local_google_map.dart` | Google Maps wrapper | 📋 TODO |

---

## Dependencies Summary

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Core RFW
  rfw: ^1.0.31

  # AG-UI Protocol SDK (SSE-based - NOT WebSocket)
  ag_ui: ^0.1.0

  # Chat UI
  dash_chat_2: ^0.0.21

  # State Management
  flutter_riverpod: ^2.6.1

  # Charts
  fl_chart: ^0.69.2

  # Media
  flutter_svg: ^2.0.17
  cached_network_image: ^3.4.1

  # Utilities
  uuid: ^4.5.1
  equatable: ^2.0.7

  # Maps (optional - add when implementing)
  google_maps_flutter: ^2.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.4
```

---

## Success Criteria

1. **Functional**: Chat interface renders both text and RFW-generated UI components seamlessly
2. **Secure**:
   - No arbitrary code execution
   - Whitelist-only widget rendering
   - SSRF prevention for network resources
   - DoS protection via depth limiting
3. **Performant**:
   - 60fps scrolling with dynamic content
   - No UI jank during payload parsing (isolate-based)
   - Efficient partial updates via DynamicContent
4. **Extensible**: New local widgets can be added without core changes
5. **Reliable**:
   - SSE stream handling with automatic retry
   - Graceful error handling
   - Fallback UI for invalid payloads

---

## Development Notes

- Start with mock/hardcoded RFW payloads before connecting to real agent
- Test each local widget independently before integration
- Use Flutter DevTools to profile performance throughout
- Security validation must be strict from Phase 1 (not bolted on later)
- Binary decoding should be in isolates from the start
- Consider feature flags for advanced components during development
- Each phase should be fully tested before moving to the next
