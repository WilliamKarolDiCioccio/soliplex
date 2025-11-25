import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_client/infrastructure/quick_agui/pending_tool_call.dart';

void main() {
  group('PendingToolCall class', () {
    test('should accept a name parameter and expose it', () {
      // Arrange & Act
      final pendingCall = PendingToolCall('tool-call-name');

      // Assert
      expect(pendingCall.name, equals('tool-call-name'));
    });

    test('args initially empty, can be appended', () {
      // Arrange
      final pendingCall = PendingToolCall('add-numbers');
      expect(pendingCall.args, equals(''));

      // Act
      pendingCall.appendArgs("{'arg1':");
      pendingCall.appendArgs(" 1, '");
      pendingCall.appendArgs("arg2'");
      pendingCall.appendArgs(": 2}");

      // Assert
      expect(pendingCall.args, equals("{'arg1': 1, 'arg2': 2}"));
    });
  });
}
