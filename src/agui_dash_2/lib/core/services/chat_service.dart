import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_models.dart';

/// Chat state containing messages and metadata.
class ChatState {
  final List<ChatMessage> messages;
  final bool isAgentTyping;
  final String? currentStreamingMessageId;
  final Map<String, String> pendingToolCalls; // toolCallId -> accumulated args

  const ChatState({
    this.messages = const [],
    this.isAgentTyping = false,
    this.currentStreamingMessageId,
    this.pendingToolCalls = const {},
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isAgentTyping,
    String? currentStreamingMessageId,
    Map<String, String>? pendingToolCalls,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isAgentTyping: isAgentTyping ?? this.isAgentTyping,
      currentStreamingMessageId:
          currentStreamingMessageId ?? this.currentStreamingMessageId,
      pendingToolCalls: pendingToolCalls ?? this.pendingToolCalls,
    );
  }
}

/// StateNotifier for managing chat state.
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(const ChatState());

  /// Add a user message.
  void addUserMessage(String text) {
    final message = ChatMessage.text(user: ChatUser.user, text: text);
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// Start a new agent text message (for streaming).
  String startAgentMessage() {
    final message = ChatMessage.text(
      user: ChatUser.agent,
      text: '',
      isStreaming: true,
    );
    state = state.copyWith(
      messages: [...state.messages, message],
      isAgentTyping: true,
      currentStreamingMessageId: message.id,
    );
    return message.id;
  }

  /// Append text to the current streaming message.
  void appendToStreamingMessage(String delta) {
    if (state.currentStreamingMessageId == null) return;

    final messages = state.messages.map((m) {
      if (m.id == state.currentStreamingMessageId) {
        return m.copyWith(text: (m.text ?? '') + delta);
      }
      return m;
    }).toList();

    state = state.copyWith(messages: messages);
  }

  /// Finalize the current streaming message.
  void finalizeStreamingMessage() {
    if (state.currentStreamingMessageId == null) return;

    final messages = state.messages.map((m) {
      if (m.id == state.currentStreamingMessageId) {
        return m.copyWith(isStreaming: false);
      }
      return m;
    }).toList();

    state = state.copyWith(
      messages: messages,
      isAgentTyping: false,
      currentStreamingMessageId: null,
    );
  }

  /// Add a loading placeholder for incoming GenUI.
  String addLoadingPlaceholder() {
    final message = ChatMessage.loading(user: ChatUser.agent);
    state = state.copyWith(
      messages: [...state.messages, message],
      isAgentTyping: true,
    );
    return message.id;
  }

  /// Start buffering a tool call (GenUI payload).
  void startToolCall(String toolCallId) {
    state = state.copyWith(
      pendingToolCalls: {...state.pendingToolCalls, toolCallId: ''},
    );
  }

  /// Append args chunk to a pending tool call.
  void appendToolCallArgs(String toolCallId, String chunk) {
    final pending = Map<String, String>.from(state.pendingToolCalls);
    pending[toolCallId] = (pending[toolCallId] ?? '') + chunk;
    state = state.copyWith(pendingToolCalls: pending);
  }

  /// Get the accumulated args for a tool call.
  String? getToolCallArgs(String toolCallId) {
    return state.pendingToolCalls[toolCallId];
  }

  /// Replace a loading placeholder with a GenUI message.
  void replaceWithGenUi(String messageId, GenUiContent content) {
    final messages = state.messages.map((m) {
      if (m.id == messageId) {
        return ChatMessage.genUi(
          id: messageId,
          user: ChatUser.agent,
          content: content,
          createdAt: m.createdAt,
        );
      }
      return m;
    }).toList();

    state = state.copyWith(messages: messages, isAgentTyping: false);
  }

  /// Replace a loading placeholder with an error.
  void replaceWithError(String messageId, String errorMessage) {
    final messages = state.messages.map((m) {
      if (m.id == messageId) {
        return ChatMessage.error(
          id: messageId,
          user: ChatUser.agent,
          errorMessage: errorMessage,
          createdAt: m.createdAt,
        );
      }
      return m;
    }).toList();

    state = state.copyWith(messages: messages, isAgentTyping: false);
  }

  /// Add a complete GenUI message (not from placeholder).
  void addGenUiMessage(GenUiContent content) {
    debugPrint(
      'ChatNotifier: Adding GenUI message - widget: ${content.widgetName}',
    );
    final message = ChatMessage.genUi(user: ChatUser.agent, content: content);
    debugPrint(
      'ChatNotifier: Created message type: ${message.type}, genUiContent: ${message.genUiContent != null}',
    );
    state = state.copyWith(messages: [...state.messages, message]);
    debugPrint('ChatNotifier: Total messages now: ${state.messages.length}');
    // Verify the message in state
    final lastMsg = state.messages.last;
    debugPrint('ChatNotifier: Last message type in state: ${lastMsg.type}');
  }

  /// Add an error message.
  void addErrorMessage(String errorMessage) {
    final message = ChatMessage.error(
      user: ChatUser.agent,
      errorMessage: errorMessage,
    );
    state = state.copyWith(
      messages: [...state.messages, message],
      isAgentTyping: false,
    );
  }

  /// Add a system/info message.
  void addSystemMessage(String text) {
    final message = ChatMessage.text(user: ChatUser.system, text: text);
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// Add a tool call message showing tool execution status.
  void addToolCallMessage(String toolName, {bool? success}) {
    final message = ChatMessage.toolCall(
      toolName: toolName,
      success: success,
    );
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// Remove a message by ID.
  void removeMessage(String messageId) {
    final messages = state.messages.where((m) => m.id != messageId).toList();
    state = state.copyWith(
      messages: messages,
      isAgentTyping: state.currentStreamingMessageId == messageId
          ? false
          : state.isAgentTyping,
      currentStreamingMessageId: state.currentStreamingMessageId == messageId
          ? null
          : state.currentStreamingMessageId,
    );
  }

  /// Update DynamicContent data for a GenUI message.
  void updateGenUiData(String messageId, Map<String, dynamic> newData) {
    final messages = state.messages.map((m) {
      if (m.id == messageId && m.type == MessageType.genUi) {
        return m.copyWith(
          genUiContent: m.genUiContent?.copyWith(data: newData),
        );
      }
      return m;
    }).toList();

    state = state.copyWith(messages: messages);
  }

  /// Clear pending tool call.
  void clearToolCall(String toolCallId) {
    final pending = Map<String, String>.from(state.pendingToolCalls);
    pending.remove(toolCallId);
    state = state.copyWith(pendingToolCalls: pending);
  }

  /// Clear all messages.
  void clearMessages() {
    state = const ChatState();
  }

  /// Load messages from thread history.
  ///
  /// This is called when resuming an existing thread to restore
  /// the conversation history to the UI.
  void loadMessages(List<ChatMessage> messages) {
    state = state.copyWith(messages: messages);
  }

  /// Set agent typing state.
  void setAgentTyping(bool isTyping) {
    state = state.copyWith(isAgentTyping: isTyping);
  }
}

/// Riverpod provider for ChatNotifier.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});
