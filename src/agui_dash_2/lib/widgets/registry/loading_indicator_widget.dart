import 'package:flutter/material.dart';

/// LoadingIndicator widget for showing loading state with optional message.
class LoadingIndicatorWidget extends StatelessWidget {
  final String? message;

  const LoadingIndicatorWidget({super.key, this.message});

  /// Create from JSON data.
  ///
  /// Expected data format:
  /// ```json
  /// {
  ///   "message": "Loading..."  // Optional message
  /// }
  /// ```
  factory LoadingIndicatorWidget.fromData(
    Map<String, dynamic> data,
    void Function(String, Map<String, dynamic>)? onEvent,
  ) {
    return LoadingIndicatorWidget(message: data['message'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[const SizedBox(height: 16), Text(message!)],
        ],
      ),
    );
  }
}
