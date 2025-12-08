import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// AG-UI Event Types as defined by the protocol.
enum AgUiEventType {
  // Text message events
  textMessageStart,
  textMessageContent,
  textMessageEnd,

  // Tool call events (for GenUI)
  toolCallStart,
  toolCallArgs,
  toolCallEnd,

  // State management
  stateUpdate,

  // Connection events
  runStarted,
  runFinished,
  runError,

  // Unknown/future event types
  unknown,
}

/// Base class for all AG-UI events.
sealed class AgUiEvent extends Equatable {
  final String? messageId;
  final DateTime timestamp;

  const AgUiEvent({
    this.messageId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _DefaultDateTime();

  AgUiEventType get type;

  @override
  List<Object?> get props => [messageId, timestamp, type];
}

// Helper class for default timestamp
class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();

  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime.now();
}

/// Text message started - signals a new text response from agent.
class TextMessageStartEvent extends AgUiEvent {
  final String role;

  const TextMessageStartEvent({
    super.messageId,
    super.timestamp,
    this.role = 'assistant',
  });

  @override
  AgUiEventType get type => AgUiEventType.textMessageStart;

  @override
  List<Object?> get props => [...super.props, role];
}

/// Text message content chunk - streaming text delta.
class TextMessageContentEvent extends AgUiEvent {
  final String delta;

  const TextMessageContentEvent({
    super.messageId,
    super.timestamp,
    required this.delta,
  });

  @override
  AgUiEventType get type => AgUiEventType.textMessageContent;

  @override
  List<Object?> get props => [...super.props, delta];
}

/// Text message ended - finalize the text message.
class TextMessageEndEvent extends AgUiEvent {
  const TextMessageEndEvent({
    super.messageId,
    super.timestamp,
  });

  @override
  AgUiEventType get type => AgUiEventType.textMessageEnd;
}

/// Tool call started - agent is generating UI component.
class ToolCallStartEvent extends AgUiEvent {
  final String toolCallId;
  final String toolName;

  const ToolCallStartEvent({
    super.messageId,
    super.timestamp,
    required this.toolCallId,
    required this.toolName,
  });

  @override
  AgUiEventType get type => AgUiEventType.toolCallStart;

  @override
  List<Object?> get props => [...super.props, toolCallId, toolName];
}

/// Tool call arguments - contains RFW payload chunk.
class ToolCallArgsEvent extends AgUiEvent {
  final String toolCallId;
  final String argsChunk;

  const ToolCallArgsEvent({
    super.messageId,
    super.timestamp,
    required this.toolCallId,
    required this.argsChunk,
  });

  @override
  AgUiEventType get type => AgUiEventType.toolCallArgs;

  @override
  List<Object?> get props => [...super.props, toolCallId, argsChunk];
}

/// Tool call ended - RFW payload complete, ready to render.
class ToolCallEndEvent extends AgUiEvent {
  final String toolCallId;

  const ToolCallEndEvent({
    super.messageId,
    super.timestamp,
    required this.toolCallId,
  });

  @override
  AgUiEventType get type => AgUiEventType.toolCallEnd;

  @override
  List<Object?> get props => [...super.props, toolCallId];
}

/// State update - partial data update for existing GenUI widget.
class StateUpdateEvent extends AgUiEvent {
  final String targetId;
  final Map<String, dynamic> updates;

  const StateUpdateEvent({
    super.messageId,
    super.timestamp,
    required this.targetId,
    required this.updates,
  });

  @override
  AgUiEventType get type => AgUiEventType.stateUpdate;

  @override
  List<Object?> get props => [...super.props, targetId, updates];
}

/// Run started - agent has begun processing.
class RunStartedEvent extends AgUiEvent {
  final String runId;

  const RunStartedEvent({
    super.messageId,
    super.timestamp,
    required this.runId,
  });

  @override
  AgUiEventType get type => AgUiEventType.runStarted;

  @override
  List<Object?> get props => [...super.props, runId];
}

/// Run finished - agent has completed processing.
class RunFinishedEvent extends AgUiEvent {
  final String runId;

  const RunFinishedEvent({
    super.messageId,
    super.timestamp,
    required this.runId,
  });

  @override
  AgUiEventType get type => AgUiEventType.runFinished;

  @override
  List<Object?> get props => [...super.props, runId];
}

/// Run error - agent encountered an error.
class RunErrorEvent extends AgUiEvent {
  final String errorCode;
  final String errorMessage;

  const RunErrorEvent({
    super.messageId,
    super.timestamp,
    required this.errorCode,
    required this.errorMessage,
  });

  @override
  AgUiEventType get type => AgUiEventType.runError;

  @override
  List<Object?> get props => [...super.props, errorCode, errorMessage];
}

/// Unknown event type - for forward compatibility.
class UnknownEvent extends AgUiEvent {
  final String rawType;
  final Map<String, dynamic> rawData;

  const UnknownEvent({
    super.messageId,
    super.timestamp,
    required this.rawType,
    required this.rawData,
  });

  @override
  AgUiEventType get type => AgUiEventType.unknown;

  @override
  List<Object?> get props => [...super.props, rawType, rawData];
}

/// Parsed GenUI payload from tool call.
class GenUiPayload extends Equatable {
  final String toolCallId;
  final String widgetName;
  final String libraryName;
  final Uint8List? libraryBlob;
  final String? libraryText;
  final Map<String, dynamic> initialData;

  const GenUiPayload({
    required this.toolCallId,
    required this.widgetName,
    this.libraryName = 'agent',
    this.libraryBlob,
    this.libraryText,
    this.initialData = const {},
  });

  bool get hasBinaryLibrary => libraryBlob != null;
  bool get hasTextLibrary => libraryText != null;
  bool get hasLibrary => hasBinaryLibrary || hasTextLibrary;

  @override
  List<Object?> get props => [
        toolCallId,
        widgetName,
        libraryName,
        libraryBlob,
        libraryText,
        initialData,
      ];
}
