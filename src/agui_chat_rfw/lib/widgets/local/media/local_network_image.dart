import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rfw/rfw.dart';

import '../../../core/utils/security_validator.dart';

/// LocalNetworkImage - RFW wrapper for cached_network_image with security.
///
/// Implements SSRF prevention via domain whitelist validation.
///
/// Expected data format:
/// ```
/// {
///   url: "https://cdn.example.com/image.jpg",  // required, must be whitelisted domain
///   width: 200,               // optional, fixed width
///   height: 200,              // optional, fixed height
///   fit: "cover",             // optional: contain, cover, fill, fitWidth, fitHeight, none
///   borderRadius: 8,          // optional, corner radius
///   placeholder: "shimmer",   // optional: shimmer, spinner, color
///   placeholderColor: 0xFFE0E0E0,  // optional, placeholder background color
///   errorWidget: "icon",      // optional: icon, text
///   fadeInDuration: 300,      // optional, fade animation duration in ms
/// }
/// ```
Widget buildLocalNetworkImage(BuildContext context, DataSource source) {
  final url = source.v<String>(<Object>['url']);

  if (url == null || url.isEmpty) {
    return _buildErrorWidget('No image URL specified');
  }

  // Security validation - SSRF prevention
  if (!SecurityValidator.isAllowedImageUrl(url)) {
    final host = Uri.tryParse(url)?.host ?? 'unknown';
    return _buildErrorWidget('Domain not allowed: $host');
  }

  // Extract properties
  final width = source.v<double>(<Object>['width']);
  final height = source.v<double>(<Object>['height']);
  final fitString = source.v<String>(<Object>['fit']) ?? 'cover';
  final borderRadius = source.v<double>(<Object>['borderRadius']) ?? 0;
  final placeholderType = source.v<String>(<Object>['placeholder']) ?? 'shimmer';
  final placeholderColorValue = source.v<int>(<Object>['placeholderColor']);
  final errorWidgetType = source.v<String>(<Object>['errorWidget']) ?? 'icon';
  final fadeInDuration = source.v<int>(<Object>['fadeInDuration']) ?? 300;

  final fit = _parseFit(fitString);
  final placeholderColor = placeholderColorValue != null
      ? Color(placeholderColorValue)
      : Colors.grey.shade200;

  Widget image = CachedNetworkImage(
    imageUrl: url,
    width: width,
    height: height,
    fit: fit,
    fadeInDuration: Duration(milliseconds: fadeInDuration),
    placeholder: (context, url) => _buildPlaceholder(
      width,
      height,
      placeholderType,
      placeholderColor,
    ),
    errorWidget: (context, url, error) => _buildError(
      width,
      height,
      errorWidgetType,
      error.toString(),
    ),
  );

  if (borderRadius > 0) {
    image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: image,
    );
  }

  return image;
}

Widget _buildPlaceholder(
  double? width,
  double? height,
  String type,
  Color color,
) {
  final container = Container(
    width: width,
    height: height,
    color: color,
  );

  switch (type.toLowerCase()) {
    case 'shimmer':
      // Animated shimmer effect
      return _ShimmerPlaceholder(width: width, height: height, color: color);
    case 'spinner':
      return Stack(
        children: [
          container,
          const Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      );
    case 'color':
    default:
      return container;
  }
}

Widget _buildError(
  double? width,
  double? height,
  String type,
  String error,
) {
  return Container(
    width: width,
    height: height,
    color: Colors.grey.shade100,
    child: Center(
      child: type == 'text'
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'Failed to load image',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            )
          : Icon(Icons.broken_image, color: Colors.grey.shade400),
    ),
  );
}

Widget _buildErrorWidget(String message) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.security, color: Colors.red.shade400, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            message,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

BoxFit _parseFit(String fit) {
  switch (fit.toLowerCase()) {
    case 'contain':
      return BoxFit.contain;
    case 'cover':
      return BoxFit.cover;
    case 'fill':
      return BoxFit.fill;
    case 'fitwidth':
      return BoxFit.fitWidth;
    case 'fitheight':
      return BoxFit.fitHeight;
    case 'none':
      return BoxFit.none;
    case 'scaledown':
      return BoxFit.scaleDown;
    default:
      return BoxFit.cover;
  }
}

/// Animated shimmer placeholder for image loading.
class _ShimmerPlaceholder extends StatefulWidget {
  final double? width;
  final double? height;
  final Color color;

  const _ShimmerPlaceholder({
    this.width,
    this.height,
    required this.color,
  });

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                widget.color,
                widget.color.withValues(alpha: 0.5),
                widget.color,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
