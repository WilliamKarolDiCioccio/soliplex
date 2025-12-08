import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rfw/rfw.dart';

import '../../../core/models/chat_models.dart';
import '../../../core/services/rfw_service.dart';

/// Widget that renders a GenUI message using RFW.
///
/// Handles layout constraints to prevent unbounded height issues
/// and manages the DynamicContent lifecycle.
class RfwMessageWidget extends ConsumerStatefulWidget {
  final GenUiContent content;
  final void Function(String eventName, Map<String, Object?> arguments)? onEvent;
  final double maxHeight;

  const RfwMessageWidget({
    super.key,
    required this.content,
    this.onEvent,
    this.maxHeight = 400,
  });

  @override
  ConsumerState<RfwMessageWidget> createState() => _RfwMessageWidgetState();
}

class _RfwMessageWidgetState extends ConsumerState<RfwMessageWidget> {
  late DynamicContent _dynamicContent;
  RemoteWidgetLibrary? _library;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWidget();
  }

  @override
  void didUpdateWidget(RfwMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update DynamicContent if data changed
    if (widget.content.data != oldWidget.content.data) {
      _updateDynamicContent();
    }

    // Reinitialize if library changed
    if (widget.content.libraryBlob != oldWidget.content.libraryBlob ||
        widget.content.libraryText != oldWidget.content.libraryText) {
      _initializeWidget();
    }
  }

  void _initializeWidget() {
    final rfwService = ref.read(rfwServiceProvider);

    // Create DynamicContent
    _dynamicContent = rfwService.createDynamicContent(widget.content.data);

    // Decode the library
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.content.hasBinaryLibrary) {
        _library = rfwService.decodeLibrary(widget.content.libraryBlob!);
      } else if (widget.content.hasTextLibrary) {
        _library = rfwService.parseTextLibrary(widget.content.libraryText!);
      }

      if (_library == null && widget.content.hasLibrary) {
        _error = 'Failed to decode widget library';
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error loading widget: $e';
      });
    }
  }

  void _updateDynamicContent() {
    // Update each key at root level to match createDynamicContent
    for (final entry in widget.content.data.entries) {
      if (entry.value != null) {
        _dynamicContent.update(entry.key, entry.value!);
      }
    }
  }

  void _handleEvent(String name, DynamicMap arguments) {
    // Pass event to parent - DynamicMap contains the raw RFW arguments
    widget.onEvent?.call(name, {'raw': arguments});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_library == null) {
      return _buildNoLibraryState();
    }

    final rfwService = ref.read(rfwServiceProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: widget.maxHeight,
        maxWidth: double.infinity,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: rfwService.buildRemoteWidget(
            library: _library!,
            libraryName: LibraryName(<String>[widget.content.libraryName]),
            widgetName: widget.content.widgetName,
            data: _dynamicContent,
            onEvent: _handleEvent,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading widget...'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoLibraryState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No widget library provided',
              style: TextStyle(color: Colors.orange.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
