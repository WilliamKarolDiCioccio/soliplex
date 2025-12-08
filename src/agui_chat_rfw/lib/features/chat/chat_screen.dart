import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:dash_chat_2/dash_chat_2.dart' as dash;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_models.dart';
import '../../core/services/agui_service.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/local_tools_service.dart';
import '../../core/services/rooms_service.dart';
import 'builders/message_builder.dart';

/// Main chat screen widget.
///
/// Integrates Dash Chat 2 with AG-UI server via SSE streaming.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final MessageBuilder _messageBuilder;

  static const String _defaultBaseUrl = 'http://localhost:8000/api/v1';

  @override
  void initState() {
    super.initState();
    _messageBuilder = MessageBuilder(
      onGenUiEvent: _handleGenUiEvent,
    );

    // Fetch rooms and configure AG-UI service on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRoomsAndConfigure();
    });
  }

  Future<void> _fetchRoomsAndConfigure() async {
    // Fetch available rooms
    final roomsNotifier = ref.read(roomsProvider.notifier);
    roomsNotifier.setBaseUrl(_defaultBaseUrl);
    await roomsNotifier.fetchRooms();

    // Select first room by default if none selected
    final rooms = ref.read(roomsProvider).rooms;
    final selectedRoom = ref.read(selectedRoomProvider);
    if (selectedRoom == null && rooms.isNotEmpty) {
      ref.read(selectedRoomProvider.notifier).state = rooms.first.id;
    }

    // Configure AG-UI with selected room
    _updateAgUiConfig();
  }

  void _updateAgUiConfig() {
    final selectedRoom = ref.read(selectedRoomProvider);
    if (selectedRoom != null) {
      ref.read(agUiConfigProvider.notifier).state = AgUiServiceConfig(
        baseUrl: _defaultBaseUrl,
        roomId: selectedRoom,
      );
      // Reset conversation when switching rooms
      ref.read(agUiServiceProvider).resetConversation();
    }
  }

  void _onRoomChanged(String? roomId) {
    if (roomId == null) return;

    ref.read(selectedRoomProvider.notifier).state = roomId;
    _updateAgUiConfig();

    // Clear chat when switching rooms
    ref.read(chatProvider.notifier).clearMessages();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to room: $roomId'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _handleGenUiEvent(String eventName, Map<String, Object?> arguments) {
    debugPrint('GenUI Event: $eventName, args: $arguments');

    // TODO: Send event back to AG-UI server for human-in-the-loop
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Event: $eventName'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleSend(dash.ChatMessage dashMessage) async {
    final text = dashMessage.text.trim();
    if (text.isEmpty) return;

    final chatNotifier = ref.read(chatProvider.notifier);
    final agUiService = ref.read(configuredAgUiServiceProvider);
    final localToolsService = ref.read(localToolsServiceProvider);

    // Add user message
    chatNotifier.addUserMessage(text);

    // Check if AG-UI is configured
    if (!agUiService.isConfigured) {
      chatNotifier.addErrorMessage('AG-UI server not configured');
      return;
    }

    try {
      // Get local tool definitions to send to server
      final localTools = localToolsService.getAgUiToolDefinitions();
      debugPrint('Sending message with ${localTools.length} local tools');

      // Stream events from AG-UI server
      final events = agUiService.sendMessage(text, localTools: localTools);

      // Process events with local tool handling
      await _processEventsWithLocalTools(events, chatNotifier, agUiService, localToolsService);
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Process AG-UI events, handling local tool calls.
  Future<void> _processEventsWithLocalTools(
    Stream<BaseEvent> events,
    ChatNotifier chatNotifier,
    AgUiService agUiService,
    LocalToolsService localToolsService,
  ) async {
    String? currentMessageId;
    String? currentToolCallId;
    String? currentToolName;
    final toolCallArgsBuffer = StringBuffer();

    await for (final event in events) {
      debugPrint('AG-UI Event: ${event.runtimeType}');

      switch (event) {
        case RunStartedEvent():
          debugPrint('AG-UI: Run started - ${event.runId}');

        case TextMessageStartEvent():
          currentMessageId = chatNotifier.startAgentMessage();
          debugPrint('AG-UI: Text message started, id=$currentMessageId');

        case TextMessageContentEvent():
          if (currentMessageId != null) {
            chatNotifier.appendToStreamingMessage(event.delta);
          }

        case TextMessageEndEvent():
          if (currentMessageId != null) {
            chatNotifier.finalizeStreamingMessage();
            currentMessageId = null;
          }

        case ToolCallStartEvent():
          currentToolCallId = event.toolCallId;
          currentToolName = event.toolCallName;
          toolCallArgsBuffer.clear();

          // Check if this is a local tool
          if (localToolsService.hasLocalTool(event.toolCallName)) {
            debugPrint('AG-UI: LOCAL tool call started - ${event.toolCallName}');
            // Add a loading message for the local tool
            currentMessageId = chatNotifier.addLoadingPlaceholder();
          } else {
            debugPrint('AG-UI: Server tool call started - ${event.toolCallName}');
            currentMessageId = chatNotifier.addLoadingPlaceholder();
          }
          chatNotifier.startToolCall(event.toolCallId);

        case ToolCallArgsEvent():
          if (currentToolCallId != null) {
            toolCallArgsBuffer.write(event.delta);
            chatNotifier.appendToolCallArgs(currentToolCallId, event.delta);
          }

        case ToolCallEndEvent():
          if (currentToolCallId != null && currentToolName != null) {
            final argsJson = chatNotifier.getToolCallArgs(currentToolCallId);
            debugPrint('AG-UI: Tool call ended - $currentToolName with args: $argsJson');

            // Check if this is a GenUI render tool (client-side widget rendering)
            if (currentToolName == 'genui_render') {
              debugPrint('AG-UI: GenUI render tool detected');

              // Remove the loading placeholder
              if (currentMessageId != null) {
                chatNotifier.removeMessage(currentMessageId);
              }

              // Parse the tool arguments
              if (argsJson != null && argsJson.isNotEmpty) {
                try {
                  final args = jsonDecode(argsJson) as Map<String, dynamic>;
                  final widgetName = args['widget_name'] as String? ?? 'Widget';
                  final libraryText = args['library_text'] as String?;
                  final libraryName = args['library_name'] as String? ?? 'agent';
                  final data = args['data'] as Map<String, dynamic>? ?? {};

                  if (libraryText != null) {
                    // Create and add the GenUI message
                    chatNotifier.addGenUiMessage(
                      GenUiContent(
                        toolCallId: currentToolCallId,
                        widgetName: widgetName,
                        libraryName: libraryName,
                        libraryText: libraryText,
                        data: data,
                      ),
                    );
                    debugPrint('AG-UI: Added GenUI message - widget: $widgetName');
                  } else {
                    chatNotifier.addErrorMessage('GenUI render: missing library_text');
                  }
                } catch (e) {
                  debugPrint('AG-UI: Failed to parse genui_render args: $e');
                  chatNotifier.addErrorMessage('Failed to parse GenUI widget: $e');
                }
              }

              // GenUI render is client-only - no result sent back to server
              chatNotifier.clearToolCall(currentToolCallId);
              chatNotifier.setAgentTyping(false); // Clear typing indicator
              currentToolCallId = null;
              currentToolName = null;
              currentMessageId = null;
            }
            // Check if this is a local tool we should execute (with server callback)
            else if (localToolsService.hasLocalTool(currentToolName)) {
              // Record the assistant's tool call in history BEFORE executing
              debugPrint('AG-UI: Recording assistant tool call - ID: $currentToolCallId, Name: $currentToolName, Args: $argsJson');
              agUiService.recordAssistantToolCall(
                toolCallId: currentToolCallId,
                toolName: currentToolName,
                arguments: argsJson ?? '{}',
              );

              // Parse arguments and execute locally
              Map<String, dynamic> args = {};
              if (argsJson != null && argsJson.isNotEmpty) {
                try {
                  args = jsonDecode(argsJson) as Map<String, dynamic>;
                } catch (e) {
                  debugPrint('Failed to parse tool args: $e');
                }
              }

              // Execute the local tool
              debugPrint('Executing local tool: $currentToolName');
              final result = await localToolsService.executeTool(
                currentToolCallId,
                currentToolName,
                args,
              );

              // Update the loading message with result info
              if (currentMessageId != null) {
                chatNotifier.removeMessage(currentMessageId);
              }

              if (result.success) {
                // Add a message showing the tool result
                chatNotifier.addSystemMessage(
                  '📍 Location retrieved: ${result.result['latitude']?.toStringAsFixed(4)}, '
                  '${result.result['longitude']?.toStringAsFixed(4)}',
                );

                // Send the result back to the server (include tools for potential follow-up calls)
                debugPrint('Sending tool result back to server...');
                final localTools = localToolsService.getAgUiToolDefinitions();
                final resultEvents = agUiService.sendToolResult(
                  result,
                  localTools: localTools,
                );

                // Process the continued response recursively
                await _processEventsWithLocalTools(
                  resultEvents,
                  chatNotifier,
                  agUiService,
                  localToolsService,
                );
              } else {
                chatNotifier.addErrorMessage('Tool error: ${result.error}');
              }

              // Cleanup after local tool execution
              chatNotifier.clearToolCall(currentToolCallId);
              currentToolCallId = null;
              currentToolName = null;
              currentMessageId = null;
            }
            // Server-side tool - just cleanup (result comes via events)
            else {
              debugPrint('AG-UI: Server-side tool call completed - $currentToolName');
              if (currentMessageId != null) {
                chatNotifier.removeMessage(currentMessageId);
              }
              chatNotifier.clearToolCall(currentToolCallId);
              chatNotifier.setAgentTyping(false); // Clear typing indicator
              currentToolCallId = null;
              currentToolName = null;
              currentMessageId = null;
            }
          }

        case StateSnapshotEvent():
          debugPrint('AG-UI: State snapshot received');

        case StateDeltaEvent():
          debugPrint('AG-UI: State delta received');

        // Thinking events - just log them, don't display
        case ThinkingStartEvent():
          debugPrint('AG-UI: Thinking started');

        case ThinkingTextMessageStartEvent():
          debugPrint('AG-UI: Thinking text started');

        case ThinkingTextMessageContentEvent():
          // Agent is thinking - could show a thinking indicator
          debugPrint('AG-UI: Thinking: ${event.delta}');

        case ThinkingTextMessageEndEvent():
          debugPrint('AG-UI: Thinking text ended');

        case ThinkingEndEvent():
          debugPrint('AG-UI: Thinking ended');

        case RunFinishedEvent():
          debugPrint('AG-UI: Run finished - ${event.runId}');

        case RunErrorEvent():
          chatNotifier.addErrorMessage(event.message);
          debugPrint('AG-UI: Run error - ${event.code}: ${event.message}');

        default:
          debugPrint('AG-UI: Unhandled event - ${event.runtimeType}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final agUiService = ref.watch(configuredAgUiServiceProvider);
    final roomsState = ref.watch(roomsProvider);
    final selectedRoom = ref.watch(selectedRoomProvider);

    // Convert our messages to Dash Chat format
    final dashMessages = chatState.messages.reversed
        .map((m) => toDashChatMessage(m))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('AG-UI Chat'),
            const SizedBox(width: 8),
            _buildConnectionIndicator(agUiService.state),
            const SizedBox(width: 16),
            // Room selector dropdown
            _buildRoomSelector(roomsState, selectedRoom),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh rooms',
            onPressed: () => ref.read(roomsProvider.notifier).fetchRooms(),
          ),
          IconButton(
            icon: const Icon(Icons.science),
            tooltip: 'Test GenUI',
            onPressed: _addTestGenUiMessage,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () {
              ref.read(chatProvider.notifier).clearMessages();
              ref.read(agUiServiceProvider).resetConversation();
            },
          ),
        ],
      ),
      body: dash.DashChat(
        currentUser: dash.ChatUser(
          id: ChatUser.user.id,
          firstName: ChatUser.user.firstName,
        ),
        onSend: _handleSend,
        messages: dashMessages,
        messageOptions: dash.MessageOptions(
          showCurrentUserAvatar: false,
          showOtherUsersAvatar: true,
          messageDecorationBuilder: (message, previousMessage, nextMessage) {
            final isUser = message.user.id == ChatUser.user.id;
            return BoxDecoration(
              color: isUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            );
          },
          // Custom builder for GenUI messages - replaces text with widget
          messageTextBuilder: (message, previousMessage, nextMessage) {
            final customProps = message.customProperties;
            final chatMessage = customProps?['chatMessage'] as ChatMessage?;

            // For non-text messages, build custom widget
            if (chatMessage != null && chatMessage.type != MessageType.text) {
              debugPrint('messageTextBuilder: Rendering ${chatMessage.type}');
              final customWidget = _messageBuilder.build(
                message,
                previousMessage: previousMessage,
                nextMessage: nextMessage,
                isAfterDateSeparator: false,
                isBeforeDateSeparator: false,
              );
              if (customWidget != null) {
                return customWidget;
              }
            }

            // Default text rendering
            return Text(
              message.text,
              style: TextStyle(
                color: message.user.id == ChatUser.user.id
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface,
              ),
            );
          },
        ),
        messageListOptions: dash.MessageListOptions(
          onLoadEarlier: () async {
            // TODO: Implement pagination if needed
          },
        ),
        inputOptions: dash.InputOptions(
          inputDecoration: InputDecoration(
            hintText: 'Type a message...',
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
          ),
          sendButtonBuilder: (onSend) {
            return IconButton(
              icon: const Icon(Icons.send),
              onPressed: onSend,
              color: Theme.of(context).colorScheme.primary,
            );
          },
        ),
        typingUsers: chatState.isAgentTyping
            ? [
                dash.ChatUser(
                  id: ChatUser.agent.id,
                  firstName: ChatUser.agent.firstName,
                ),
              ]
            : [],
      ),
    );
  }

  Widget _buildConnectionIndicator(AgUiConnectionState state) {
    Color color;
    String tooltip;

    switch (state) {
      case AgUiConnectionState.connected:
        color = Colors.green;
        tooltip = 'Connected';
      case AgUiConnectionState.streaming:
        color = Colors.blue;
        tooltip = 'Streaming';
      case AgUiConnectionState.connecting:
        color = Colors.orange;
        tooltip = 'Connecting...';
      case AgUiConnectionState.error:
        color = Colors.red;
        tooltip = 'Error';
      case AgUiConnectionState.disconnected:
        color = Colors.grey;
        tooltip = 'Disconnected';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildRoomSelector(RoomsState roomsState, String? selectedRoom) {
    if (roomsState.isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (roomsState.error != null) {
      return Tooltip(
        message: 'Error: ${roomsState.error}',
        child: IconButton(
          icon: const Icon(Icons.error_outline, color: Colors.red),
          onPressed: () => ref.read(roomsProvider.notifier).fetchRooms(),
        ),
      );
    }

    if (roomsState.rooms.isEmpty) {
      return const Text(
        'No rooms',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: selectedRoom,
        hint: const Text('Select room'),
        underline: const SizedBox(),
        isDense: true,
        icon: const Icon(Icons.arrow_drop_down),
        items: roomsState.rooms.map((room) {
          return DropdownMenuItem<String>(
            value: room.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.meeting_room, size: 16),
                const SizedBox(width: 8),
                Text(room.name),
              ],
            ),
          );
        }).toList(),
        onChanged: _onRoomChanged,
      ),
    );
  }

  /// Add a test GenUI message for development.
  void _addTestGenUiMessage() {
    debugPrint('TEST: _addTestGenUiMessage called');
    final chatNotifier = ref.read(chatProvider.notifier);

    // Add a simple test GenUI message with text library
    debugPrint('TEST: Adding GenUI message...');
    chatNotifier.addGenUiMessage(
      GenUiContent(
        toolCallId: 'test-${DateTime.now().millisecondsSinceEpoch}',
        widgetName: 'TestWidget',
        libraryName: 'test',
        libraryText: '''
import core.widgets;
import material;

widget TestWidget = Container(
  padding: [16.0, 16.0, 16.0, 16.0],
  child: Column(
    mainAxisSize: "min",
    crossAxisAlignment: "start",
    children: [
      Text(
        text: "Hello from RFW!",
        style: {
          fontSize: 18.0,
          fontWeight: "bold",
        },
      ),
      SizedBox(height: 8.0),
      Text(text: "This widget was generated dynamically."),
      SizedBox(height: 16.0),
      ElevatedButton(
        onPressed: event "button_pressed" {},
        child: Text(text: "Click Me"),
      ),
    ],
  ),
);
''',
        data: {},
      ),
    );
  }
}
