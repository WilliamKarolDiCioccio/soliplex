import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rfw/rfw.dart';

import '../../../core/utils/security_validator.dart';

/// LocalSvgImage - RFW wrapper for flutter_svg.
///
/// Supports both bundled assets and network SVGs with security validation.
///
/// Expected data format:
/// ```
/// {
///   assetName: "assets/icons/logo.svg",  // for bundled assets
///   // OR
///   url: "https://cdn.example.com/icon.svg",  // for network SVGs
///
///   width: 100,             // optional, fixed width
///   height: 100,            // optional, fixed height
///   fit: "contain",         // optional: contain, cover, fill, fitWidth, fitHeight, none
///   color: 0xFF2196F3,      // optional, color filter
///   alignment: "center",    // optional: center, topLeft, topRight, etc.
///   placeholderColor: 0xFFE0E0E0,  // optional, placeholder color while loading
/// }
/// ```
Widget buildLocalSvgImage(BuildContext context, DataSource source) {
  final assetName = source.v<String>(<Object>['assetName']);
  final url = source.v<String>(<Object>['url']);

  if (assetName == null && url == null) {
    return _buildErrorWidget('No SVG source specified');
  }

  // Extract common properties
  final width = source.v<double>(<Object>['width']);
  final height = source.v<double>(<Object>['height']);
  final fitString = source.v<String>(<Object>['fit']) ?? 'contain';
  final colorValue = source.v<int>(<Object>['color']);
  final alignmentString = source.v<String>(<Object>['alignment']) ?? 'center';
  final placeholderColorValue = source.v<int>(<Object>['placeholderColor']);

  final fit = _parseFit(fitString);
  final alignment = _parseAlignment(alignmentString);
  final colorFilter = colorValue != null
      ? ColorFilter.mode(Color(colorValue), BlendMode.srcIn)
      : null;
  final placeholderColor = placeholderColorValue != null
      ? Color(placeholderColorValue)
      : Colors.grey.shade200;

  // Asset-based SVG
  if (assetName != null) {
    return SvgPicture.asset(
      assetName,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      colorFilter: colorFilter,
      placeholderBuilder: (context) => _buildPlaceholder(width, height, placeholderColor),
    );
  }

  // Network SVG - with security validation
  if (url != null) {
    if (!SecurityValidator.isAllowedImageUrl(url)) {
      return _buildErrorWidget('URL not allowed: ${Uri.parse(url).host}');
    }

    return SvgPicture.network(
      url,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      colorFilter: colorFilter,
      placeholderBuilder: (context) => _buildPlaceholder(width, height, placeholderColor),
    );
  }

  return _buildErrorWidget('Invalid SVG configuration');
}

Widget _buildPlaceholder(double? width, double? height, Color color) {
  return Container(
    width: width ?? 48,
    height: height ?? 48,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

Widget _buildErrorWidget(String message) {
  return Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image, color: Colors.red.shade400, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            message,
            style: TextStyle(color: Colors.red.shade700, fontSize: 12),
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
      return BoxFit.contain;
  }
}

Alignment _parseAlignment(String alignment) {
  switch (alignment.toLowerCase()) {
    case 'topleft':
      return Alignment.topLeft;
    case 'topcenter':
      return Alignment.topCenter;
    case 'topright':
      return Alignment.topRight;
    case 'centerleft':
      return Alignment.centerLeft;
    case 'center':
      return Alignment.center;
    case 'centerright':
      return Alignment.centerRight;
    case 'bottomleft':
      return Alignment.bottomLeft;
    case 'bottomcenter':
      return Alignment.bottomCenter;
    case 'bottomright':
      return Alignment.bottomRight;
    default:
      return Alignment.center;
  }
}
