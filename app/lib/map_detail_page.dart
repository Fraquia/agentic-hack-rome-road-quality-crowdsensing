import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'map_store.dart';

class MapDetailPage extends StatelessWidget {
  final GeneratedMap map;

  const MapDetailPage({super.key, required this.map});

  @override
  Widget build(BuildContext context) {
    final data = map.data;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(map.title, style: const TextStyle(fontSize: 16)),
            Text(map.subtitle,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: data.center,
              initialZoom: 16,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.hackathon.roadquality',
              ),
              PolylineLayer(
                polylines: data.roads.map((r) => Polyline(
                  points: r.points,
                  color: r.color.withValues(alpha: 0.85),
                  strokeWidth: r.strokeWidth,
                  strokeCap: StrokeCap.round,
                )).toList(),
              ),
              MarkerLayer(
                markers: data.markers.map((m) => Marker(
                  point: m.position,
                  width: 100,
                  height: 48,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_pin, color: m.color, size: 28),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          m.label.replaceAll('_', '\n'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: m.color,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ],
          ),
          const Positioned(
            left: 16,
            bottom: 16,
            child: _Legend(),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  static const _entries = [
    ('Percorso',       Color(0xFF78909C)), // blueGrey.shade400
    ('Usura',          Color(0xFFF9A825)), // yellow.shade700
    ('Dosso',          Colors.orange),
    ('Buca',           Colors.red),
  ];

  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16, height: 8,
                  decoration: BoxDecoration(
                    color: e.$2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 6),
                Text(e.$1, style: const TextStyle(fontSize: 11)),
              ],
            ),
          )).toList(),
        ),
      ),
    );
  }
}
