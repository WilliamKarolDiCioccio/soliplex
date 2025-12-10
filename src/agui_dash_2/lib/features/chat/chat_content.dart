import 'package:ag_ui/ag_ui.dart' as ag_ui;
import 'package:dash_chat_2/dash_chat_2.dart' as dash;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chat_models.dart';
import '../../core/services/agui_service.dart';
import '../../core/services/canvas_service.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/context_pane_service.dart';
import '../../core/services/local_tools_service.dart';
import 'builders/message_builder.dart';

/// Chat content widget that can be embedded in various layouts.
///
/// Contains the DashChat widget and handles message sending/receiving.
/// Can be used standalone or within layout containers.
class ChatContent extends ConsumerStatefulWidget {
  const ChatContent({super.key});

  @override
  ConsumerState<ChatContent> createState() => _ChatContentState();
}

class _ChatContentState extends ConsumerState<ChatContent> {
  late final MessageBuilder _messageBuilder;

  @override
  void initState() {
    super.initState();
    _messageBuilder = MessageBuilder(onGenUiEvent: _handleGenUiEvent);
  }

  void _handleGenUiEvent(String eventName, Map<String, Object?> arguments) {
    debugPrint('GenUI Event: $eventName, args: $arguments');

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
    final contextNotifier = ref.read(contextPaneProvider.notifier);
    final canvasNotifier = ref.read(canvasProvider.notifier);

    // Add user message
    chatNotifier.addUserMessage(text);
    contextNotifier.addTextMessage(text, isUser: true);

    // Check if AG-UI is configured
    if (!agUiService.isConfigured) {
      chatNotifier.addErrorMessage('AG-UI server not configured');
      return;
    }

    try {
      // Use the chat() method which handles tool loop internally
      await agUiService.chat(
        text,
        localToolsService: localToolsService,
        onEvent: (event) {
          if (!mounted) return;
          _processEvent(event, chatNotifier, contextNotifier, canvasNotifier);
        },
        uiToolHandler: (toolName, args) async {
          debugPrint('UI Tool Handler: $toolName with args: $args');
          return _handleUiTool(
            toolName,
            args,
            chatNotifier,
            canvasNotifier,
            contextNotifier,
          );
        },
      );
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        chatNotifier.addErrorMessage('Error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // State for tracking messages per AG-UI messageId
  // Maps AG-UI event messageId -> our internal ChatMessage id
  final Map<String, String> _messageIdMap = {};
  final Map<String, StringBuffer> _textBuffers = {};

  /// Process a single AG-UI event.
  void _processEvent(
    ag_ui.BaseEvent event,
    ChatNotifier chatNotifier,
    ContextPaneNotifier contextNotifier,
    CanvasNotifier canvasNotifier,
  ) {
    debugPrint('AG-UI Event: ${event.runtimeType}');

    switch (event) {
      case ag_ui.RunStartedEvent():
        debugPrint('AG-UI: Run started - ${event.runId}');
        contextNotifier.addAgUiEvent('Run Started', summary: event.runId);

      case ag_ui.TextMessageStartEvent():
        final aguiMessageId = event.messageId;
        debugPrint('AG-UI: TextMessageStartEvent received, messageId=$aguiMessageId');
        final chatMessageId = chatNotifier.startAgentMessage();
        _messageIdMap[aguiMessageId] = chatMessageId;
        _textBuffers[aguiMessageId] = StringBuffer();
        debugPrint('AG-UI: Text message started, aguiId=$aguiMessageId -> chatId=$chatMessageId');

      case ag_ui.TextMessageContentEvent():
        final aguiMessageId = event.messageId;
        final chatMessageId = _messageIdMap[aguiMessageId];
        debugPrint('AG-UI: TextMessageContentEvent received, messageId=$aguiMessageId, delta="${event.delta}"');
        if (chatMessageId != null) {
          chatNotifier.appendToStreamingMessage(chatMessageId, event.delta);
          _textBuffers[aguiMessageId]?.write(event.delta);
        } else {
          debugPrint('AG-UI: WARNING - TextMessageContentEvent but no mapping for messageId=$aguiMessageId');
        }

      case ag_ui.TextMessageEndEvent():
        final aguiMessageId = event.messageId;
        final chatMessageId = _messageIdMap[aguiMessageId];
        debugPrint('AG-UI: TextMessageEndEvent received, messageId=$aguiMessageId');
        if (chatMessageId != null) {
          chatNotifier.finalizeStreamingMessage(chatMessageId);
          final text = _textBuffers[aguiMessageId]?.toString() ?? '';
          contextNotifier.addTextMessage(text, isUser: false);
          _messageIdMap.remove(aguiMessageId);
          _textBuffers.remove(aguiMessageId);
        } else {
          debugPrint('AG-UI: WARNING - TextMessageEndEvent but no mapping for messageId=$aguiMessageId');
        }

      case ag_ui.ToolCallStartEvent():
        debugPrint('AG-UI: Tool call started - ${event.toolCallName}');
        contextNotifier.addToolCall(event.toolCallName, summary: 'started');

      case ag_ui.ToolCallArgsEvent():
        // Args are handled by Thread class, just log here
        debugPrint('AG-UI: Tool call args - ${event.toolCallId}');

      case ag_ui.ToolCallEndEvent():
        debugPrint('AG-UI: Tool call ended - ${event.toolCallId}');

      case ag_ui.ToolCallResultEvent():
        debugPrint('AG-UI: Tool result received');
        contextNotifier.addAgUiEvent('Tool Result');

      case ag_ui.StateSnapshotEvent():
        debugPrint('AG-UI: State snapshot received');
        final stateData = event.snapshot as Map<String, dynamic>? ?? {};
        contextNotifier.updateState(stateData);

      case ag_ui.StateDeltaEvent():
        debugPrint('AG-UI: State delta received');
        final delta = event.delta as List<dynamic>? ?? [];
        if (delta.isNotEmpty && delta.first is Map<String, dynamic>) {
          contextNotifier.applyDelta(delta.first as Map<String, dynamic>);
        }

      case ag_ui.ActivitySnapshotEvent():
        debugPrint(
          'AG-UI: Activity snapshot received - ${event.activities.length} activities',
        );
        contextNotifier.addAgUiEvent(
          'Activity Snapshot',
          summary: '${event.activities.length} activities',
        );

      case ag_ui.ThinkingStartEvent():
        debugPrint('AG-UI: Thinking started');
        contextNotifier.addAgUiEvent('Thinking');

      case ag_ui.ThinkingTextMessageStartEvent():
        debugPrint('AG-UI: Thinking text started');

      case ag_ui.ThinkingTextMessageContentEvent():
        debugPrint('AG-UI: Thinking: ${event.delta}');

      case ag_ui.ThinkingTextMessageEndEvent():
        debugPrint('AG-UI: Thinking text ended');

      case ag_ui.ThinkingEndEvent():
        debugPrint('AG-UI: Thinking ended');

      case ag_ui.RunFinishedEvent():
        debugPrint('AG-UI: Run finished - ${event.runId}');
        contextNotifier.addAgUiEvent('Run Finished');

      case ag_ui.RunErrorEvent():
        chatNotifier.addErrorMessage(event.message);
        contextNotifier.addAgUiEvent('Error', summary: event.message);
        debugPrint('AG-UI: Run error - ${event.code}: ${event.message}');

      // Handle custom events for genui_render and canvas_render
      case ag_ui.CustomEvent():
        _handleCustomEvent(
          event,
          chatNotifier,
          contextNotifier,
          canvasNotifier,
        );

      default:
        debugPrint('AG-UI: Unhandled event - ${event.runtimeType}: $event');
    }
  }

  /// Handle UI tools (canvas_render, genui_render) that need Riverpod access.
  Map<String, dynamic> _handleUiTool(
    String toolName,
    Map<String, dynamic> args,
    ChatNotifier chatNotifier,
    CanvasNotifier canvasNotifier,
    ContextPaneNotifier contextNotifier,
  ) {
    debugPrint('_handleUiTool: $toolName');

    if (toolName == 'genui_render') {
      final widgetName = args['widget_name'] as String? ?? 'Widget';
      final data = args['data'] as Map<String, dynamic>? ?? {};

      chatNotifier.addGenUiMessage(
        GenUiContent(
          toolCallId: 'tool-${DateTime.now().millisecondsSinceEpoch}',
          widgetName: widgetName,
          data: data,
        ),
      );
      contextNotifier.addGenUiRender(widgetName);
      return {'rendered': true, 'widget': widgetName};
    } else if (toolName == 'canvas_render') {
      final widgetName = args['widget_name'] as String? ?? 'Widget';
      final data = args['data'] as Map<String, dynamic>? ?? {};
      final position = args['position'] as String? ?? 'append';

      debugPrint(
        '_handleUiTool canvas_render: widget=$widgetName, position=$position',
      );

      switch (position) {
        case 'clear':
          canvasNotifier.clear();
          break;
        case 'replace':
          canvasNotifier.replaceAll(widgetName, data);
          break;
        default:
          canvasNotifier.addItem(widgetName, data);
      }
      contextNotifier.addCanvasRender(widgetName, position);
      return {'rendered': true, 'widget': widgetName, 'position': position};
    }

    return {'error': 'Unknown UI tool: $toolName'};
  }

  /// Handle custom events (genui_render, canvas_render).
  /// NOTE: These are now handled via uiToolHandler, so CustomEvents are ignored
  /// to prevent double-rendering.
  void _handleCustomEvent(
    ag_ui.CustomEvent event,
    ChatNotifier chatNotifier,
    ContextPaneNotifier contextNotifier,
    CanvasNotifier canvasNotifier,
  ) {
    final eventName = event.name;

    debugPrint('AG-UI: Custom event - $eventName (ignored - handled via tool)');

    // genui_render and canvas_render are handled via _handleUiTool
    // CustomEvents for these are ignored to prevent double-rendering
    if (eventName == 'genui_render' || eventName == 'canvas_render') {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Convert our messages to Dash Chat format
    final dashMessages = chatState.messages.reversed
        .map((m) => toDashChatMessage(m))
        .toList();

    // Use LayoutBuilder to get actual available width for the chat column
    return LayoutBuilder(
      builder: (context, constraints) {
        // Constrain message bubbles to 70% of available chat width
        final messageMaxWidth = constraints.maxWidth * 0.7;

        return dash.DashChat(
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
            // Constrain message width to 70% of actual available space
            maxWidth: messageMaxWidth,
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
        sendOnEnter: true,
        inputDecoration: InputDecoration(
          hintText: 'Type a message, SHIFT+ENTER multiple lines',
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
        );
      },
    );
  }
}
