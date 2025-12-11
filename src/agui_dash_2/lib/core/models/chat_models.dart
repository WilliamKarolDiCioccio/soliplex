import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Represents a user in the chat system.
class ChatUser extends Equatable {
  final String id;
  final String? firstName;
  final String? lastName;
  final String? profileImage;
  final Map<String, dynamic>? customProperties;

  const ChatUser({
    required this.id,
    this.firstName,
    this.lastName,
    this.profileImage,
    this.customProperties,
  });

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return firstName ?? lastName ?? id;
  }

  @override
  List<Object?> get props => [id, firstName, lastName, profileImage];

  /// Predefined user for the human user.
  static const ChatUser user = ChatUser(id: 'user', firstName: 'You');

  /// Predefined user for the AI agent.
  static const ChatUser agent = ChatUser(id: 'agent', firstName: 'Agent');

  /// Predefined user for system messages.
  static const ChatUser system = ChatUser(id: 'system', firstName: 'System');
}

/// Type of chat message content.
enum MessageType { text, genUi, loading, error, toolCall }

/// Represents a message in the chat.
class ChatMessage extends Equatable {
  final String id;
  final ChatUser user;
  final DateTime createdAt;
  final MessageType type;
  final String? text;
  final GenUiContent? genUiContent;
  final String? errorMessage;
  final bool isStreaming;
  final String? toolCallName;
  final bool? toolCallSuccess;

  ChatMessage({
    String? id,
    required this.user,
    DateTime? createdAt,
    this.type = MessageType.text,
    this.text,
    this.genUiContent,
    this.errorMessage,
    this.isStreaming = false,
    this.toolCallName,
    this.toolCallSuccess,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  /// Create a text message.
  factory ChatMessage.text({
    String? id,
    required ChatUser user,
    required String text,
    DateTime? createdAt,
    bool isStreaming = false,
  }) {
    return ChatMessage(
      id: id,
      user: user,
      text: text,
      type: MessageType.text,
      createdAt: createdAt,
      isStreaming: isStreaming,
    );
  }

  /// Create a GenUI message.
  factory ChatMessage.genUi({
    String? id,
    required ChatUser user,
    required GenUiContent content,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id,
      user: user,
      genUiContent: content,
      type: MessageType.genUi,
      createdAt: createdAt,
    );
  }

  /// Create a loading placeholder message.
  factory ChatMessage.loading({
    String? id,
    required ChatUser user,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id,
      user: user,
      type: MessageType.loading,
      createdAt: createdAt,
    );
  }

  /// Create an error message.
  factory ChatMessage.error({
    String? id,
    required ChatUser user,
    required String errorMessage,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id,
      user: user,
      type: MessageType.error,
      errorMessage: errorMessage,
      createdAt: createdAt,
    );
  }

  /// Create a tool call message.
  factory ChatMessage.toolCall({
    String? id,
    required String toolName,
    bool? success,
    DateTime? createdAt,
  }) {
    return ChatMessage(
      id: id,
      user: ChatUser.system,
      type: MessageType.toolCall,
      toolCallName: toolName,
      toolCallSuccess: success,
      createdAt: createdAt,
    );
  }

  /// Create a copy with updated fields.
  ChatMessage copyWith({
    String? id,
    ChatUser? user,
    DateTime? createdAt,
    MessageType? type,
    String? text,
    GenUiContent? genUiContent,
    String? errorMessage,
    bool? isStreaming,
    String? toolCallName,
    bool? toolCallSuccess,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      user: user ?? this.user,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      text: text ?? this.text,
      genUiContent: genUiContent ?? this.genUiContent,
      errorMessage: errorMessage ?? this.errorMessage,
      isStreaming: isStreaming ?? this.isStreaming,
      toolCallName: toolCallName ?? this.toolCallName,
      toolCallSuccess: toolCallSuccess ?? this.toolCallSuccess,
    );
  }

  @override
  List<Object?> get props => [
    id,
    user,
    createdAt,
    type,
    text,
    genUiContent,
    errorMessage,
    isStreaming,
    toolCallName,
    toolCallSuccess,
  ];
}

/// Content for a GenUI message.
///
/// Used with the native widget registry to render widgets
/// based on widgetName and data.
class GenUiContent extends Equatable {
  final String toolCallId;
  final String widgetName;
  final Map<String, dynamic> data;

  const GenUiContent({
    required this.toolCallId,
    required this.widgetName,
    this.data = const {},
  });

  GenUiContent copyWith({
    String? toolCallId,
    String? widgetName,
    Map<String, dynamic>? data,
  }) {
    return GenUiContent(
      toolCallId: toolCallId ?? this.toolCallId,
      widgetName: widgetName ?? this.widgetName,
      data: data ?? this.data,
    );
  }

  @override
  List<Object?> get props => [toolCallId, widgetName, data];
}
