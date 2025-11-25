class TextMessageBuffer {
  final StringBuffer messageId = StringBuffer();
  final StringBuffer _buffer = StringBuffer();

  TextMessageBuffer();

  void start(String id) {
    messageId.clear();
    messageId.write(id);
    _buffer.clear();
  }

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
