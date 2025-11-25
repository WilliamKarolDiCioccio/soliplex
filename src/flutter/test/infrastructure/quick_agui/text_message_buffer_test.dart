import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_client/infrastructure/quick_agui/text_message_buffer.dart';

void main() {
  group('TextMessageBuffer class', () {
    test('should be instantiable', () {
      // Arrange & Act
      final buffer = TextMessageBuffer('message-id');

      // Assert
      expect(buffer.messageId, equals('message-id'));
      expect(buffer.content, equals(''));
    });

    test('can add to the content', () {
      // Arrange
      final messageId = 'message-id';
      final buffer = TextMessageBuffer(messageId);

      // Act
      buffer.add(messageId, 'test');
      buffer.add(messageId, ' adding');
      buffer.add(messageId, ' a word');

      // Assert
      expect(buffer.messageId, equals('message-id'));
      expect(buffer.content, equals('test adding a word'));
    });

    test('throws if messsage id does not match', () {
      // Arrange
      final messageId = 'message-id';
      final buffer = TextMessageBuffer(messageId);

      // Act
      buffer.add(messageId, 'test');
      buffer.add(messageId, ' adding');

      // Assert
      expect(()=>buffer.add('different-$messageId', ' a word'),  throwsA(isA<StateError>())) ;
    });
  });
}
