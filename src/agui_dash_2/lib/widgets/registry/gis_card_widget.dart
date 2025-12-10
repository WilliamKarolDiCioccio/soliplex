import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'gis_map_modal.dart';

/// GIS Card widget for displaying a location on an OpenStreetMap.
///
/// Shows a static map thumbnail in the chat that opens an interactive
/// map modal when tapped.
class GISCardWidget extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double zoom;
  final String? title;
  final bool showAccuracyCircle;
  final VoidCallback? onTap;

  const GISCardWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.zoom = 15,
    this.title,
    this.showAccuracyCircle = true,
    this.onTap,
  });

  /// Create from JSON data.
  ///
  /// Expected data format:
  /// ```json
  /// {
  ///   "latitude": 37.7749,
  ///   "longitude": -122.4194,
  ///   "accuracy": 10.0,
  ///   "zoom": 15,
  ///   "title": "Your Location",
  ///   "showAccuracyCircle": true
  /// }
  /// ```
  factory GISCardWidget.fromData(
    Map<String, dynamic> data,
    void Function(String, Map<String, dynamic>)? onEvent,
  ) {
    return GISCardWidget(
      latitude: _parseDouble(data['latitude']) ?? 0.0,
      longitude: _parseDouble(data['longitude']) ?? 0.0,
      accuracy: _parseDouble(data['accuracy']),
      zoom: _parseDouble(data['zoom']) ?? 15.0,
      title: data['title'] as String?,
      showAccuracyCircle: data['showAccuracyCircle'] as bool? ?? true,
      onTap: onEvent != null
          ? () => onEvent('tap', {
                'latitude': data['latitude'],
                'longitude': data['longitude'],
              })
          : null,
    );
  }

  /// Parse a value that might be a num or a String to double.
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  void _openMapModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => GISMapModal(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        initialZoom: zoom,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(latitude, longitude);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openMapModal(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.map,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title ?? 'Location',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_full,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
            // Static Map
            SizedBox(
              height: 180,
              width: double.infinity,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: zoom,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    // OpenStreetMap tiles
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.agui_dash_2',
                    ),
                    // Accuracy circle
                    if (showAccuracyCircle && accuracy != null && accuracy! > 0)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: center,
                            radius: accuracy!,
                            useRadiusInMeter: true,
                            color: Colors.blue.withAlpha(40),
                            borderColor: Colors.blue.withAlpha(150),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    // Location marker
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: center,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Footer hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to open interactive map',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
