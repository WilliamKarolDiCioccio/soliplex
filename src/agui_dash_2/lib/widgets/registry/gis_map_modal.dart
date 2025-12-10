import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Modal dialog with an interactive OpenStreetMap view.
///
/// Shows the location with a marker and optional accuracy circle.
/// Supports pan and zoom interactions.
class GISMapModal extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double initialZoom;
  final String? title;

  const GISMapModal({
    super.key,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.initialZoom = 15,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final center = LatLng(latitude, longitude);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.map,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title ?? 'Location',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            // Map
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              width: MediaQuery.of(context).size.width * 0.9,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: initialZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  // OpenStreetMap tiles
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.agui_dash_2',
                  ),
                  // Accuracy circle
                  if (accuracy != null && accuracy! > 0)
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
            // Coordinates footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.my_location,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (accuracy != null) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.gps_fixed,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '±${accuracy!.toStringAsFixed(1)}m',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
