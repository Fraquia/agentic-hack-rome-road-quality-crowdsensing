import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'anomaly.dart';
import 'road_map_service.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _store   = AnomalyStore();
  final _service = RoadMapService();

  RoadMapData? _mapData;
  bool   _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_store.count > 0) _loadMap();
  }

  Future<void> _loadMap() async {
    if (_store.anomalies.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.build(_store.anomalies);
      if (mounted) setState(() { _mapData = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mappa qualità stradale'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_store.count > 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Aggiorna mappa',
              onPressed: _loading ? null : _loadMap,
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _store.count > 0 ? _legend() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  Widget _buildBody() {
    if (_store.count == 0) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 72, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Nessun dato ancora.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Avvia il monitoraggio per raccogliere anomalie stradali.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Interrogo OpenStreetMap…'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 56, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Errore: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadMap,
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }

    if (_mapData == null) {
      return const Center(child: Text('Premi aggiorna per caricare la mappa.'));
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: _mapData!.center,
        initialZoom: 16,
      ),
      children: [
        // OSM tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.hackathon.roadquality',
        ),

        // Strade colorate per severità
        PolylineLayer(
          polylines: _mapData!.roads.map((r) => Polyline(
            points: r.points,
            color: r.color.withOpacity(0.85),
            strokeWidth: r.strokeWidth,
            strokeCap: StrokeCap.round,
          )).toList(),
        ),

        // Marker anomalie con etichetta
        MarkerLayer(
          markers: _mapData!.markers.map((m) => Marker(
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
                    color: Colors.white.withOpacity(0.85),
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
    );
  }

  Widget _legend() {
    final entries = [
      ('Nessun difetto', Colors.green),
      ('Usura',          Colors.yellow.shade700),
      ('Dosso',          Colors.orange),
      ('Buca',           Colors.red),
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.map((e) => Padding(
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
      ),
    );
  }
}
