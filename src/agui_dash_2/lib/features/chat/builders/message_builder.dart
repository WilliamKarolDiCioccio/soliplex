import 'package:dash_chat_2/dash_chat_2.dart' as dash;
import 'package:flutter/material.dart';

import '../../../core/models/chat_models.dart';
import '../widgets/genui_message_widget.dart';

/// Custom message builder for Dash Chat 2.
///
/// Routes messages to appropriate widgets based on type:
/// - Text messages → default text bubble
/// - GenUI messages → GenUiMessageWidget (native widget registry)
/// - Loading messages → loading indicator
/// - Error messages → error display
class MessageBuilder {
  final void Function(String eventName, Map<String, Object?> arguments)?
  onGenUiEvent;

  MessageBuilder({this.onGenUiEvent});

  /// Build a custom message widget based on message type.
  Widget? build(
    dash.ChatMessage dashMessage, {
    dash.ChatMessage? previousMessage,
    dash.ChatMessage? nextMessage,
    required bool isAfterDateSeparator,
    required bool isBeforeDateSeparator,
  }) {
    // Extract our custom message from customProperties
    final customProps = dashMessage.customProperties;
    if (customProps == null) {
      debugPrint('MessageBuilder: No customProperties');
      return null;
    }

    final chatMessage = customProps['chatMessage'] as ChatMessage?;
    if (chatMessage == null) {
      debugPrint('MessageBuilder: No chatMessage in customProperties');
      return null;
    }

    debugPrint('MessageBuilder: Building widget for type: ${chatMessage.type}');

    return switch (chatMessage.type) {
      MessageType.text => null, // Use default text bubble
      MessageType.genUi => _buildGenUiMessage(chatMessage),
      MessageType.loading => _buildLoadingMessage(),
      MessageType.error => _buildErrorMessage(chatMessage),
      MessageType.toolCall => _buildToolCallMessage(chatMessage),
    };
  }

  Widget _buildGenUiMessage(ChatMessage message) {
    if (message.genUiContent == null) {
      return _buildErrorMessage(
        message.copyWith(errorMessage: 'Missing GenUI content'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: GenUiMessageWidget(
        content: message.genUiContent!,
        onEvent: onGenUiEvent,
      ),
    );
  }

  Widget _buildLoadingMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Agent is thinking...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMessage(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message.errorMessage ?? 'An error occurred',
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCallMessage(ChatMessage message) {
    final toolName = message.toolCallName ?? 'Unknown Tool';
    final formattedName = _formatToolName(toolName);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.build_circle_outlined,
              color: Colors.blueGrey.shade600,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'System',
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Executing $formattedName',
                style: TextStyle(
                  color: Colors.blueGrey.shade600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format tool name for display (convert snake_case to Title Case).
  String _formatToolName(String name) {
    return name
        .split('_')
        .map((word) => word.isEmpty
            ? ''
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}

/// Convert our ChatMessage to Dash Chat's ChatMessage format.
dash.ChatMessage toDashChatMessage(ChatMessage message) {
  debugPrint(
    'toDashChatMessage: id=${message.id}, type=${message.type}, hasGenUiContent=${message.genUiContent != null}',
  );

  // For non-text messages, use placeholder text so messageTextBuilder gets called
  String displayText;
  switch (message.type) {
    case MessageType.text:
      displayText = message.text ?? '';
      debugPrint('toDashChatMessage: TEXT message');
    case MessageType.genUi:
      displayText = '[Widget]'; // Placeholder - will be replaced by builder
      debugPrint(
        'toDashChatMessage: GENUI widget=${message.genUiContent?.widgetName}',
      );
    case MessageType.loading:
      displayText = '[Loading...]';
      debugPrint('toDashChatMessage: LOADING message');
    case MessageType.error:
      displayText = message.errorMessage ?? '[Error]';
      debugPrint('toDashChatMessage: ERROR message=${message.errorMessage}');
    case MessageType.toolCall:
      displayText = '[Tool: ${message.toolCallName}]';
      debugPrint('toDashChatMessage: TOOLCALL message=${message.toolCallName}');
  }

  return dash.ChatMessage(
    user: dash.ChatUser(
      id: message.user.id,
      firstName: message.user.firstName,
      lastName: message.user.lastName,
      profileImage: message.user.profileImage,
    ),
    text: displayText,
    createdAt: message.createdAt,
    customProperties: {'chatMessage': message, 'type': message.type.name},
  );
}

/// Convert Dash Chat's ChatUser to our ChatUser format.
ChatUser fromDashChatUser(dash.ChatUser dashUser) {
  return ChatUser(
    id: dashUser.id,
    firstName: dashUser.firstName,
    lastName: dashUser.lastName,
    profileImage: dashUser.profileImage,
  );
}
