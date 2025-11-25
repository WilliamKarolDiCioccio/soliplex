class TextMessageBuffer {
  final String messageId;
  final StringBuffer _buffer = StringBuffer();

  TextMessageBuffer(this.messageId);

  void add(String id, String content) {
    if (id != messageId.toString()) {
      throw StateError(
        'Incoming message id ($id) does not match with original message id ($messageId)',
      );
    }

    _buffer.write(content);
  }

  String get content => _buffer.toString();
}
