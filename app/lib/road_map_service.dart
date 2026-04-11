import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'anomaly.dart';

/// Risultato del servizio mappa: strade colorate + marker anomalie.
class RoadMapData {
  final List<ColoredRoad> roads;
  final List<AnomalyMarker> markers;
  final LatLng center;

  const RoadMapData({
    required this.roads,
    required this.markers,
    required this.center,
  });
}

class ColoredRoad {
  final List<LatLng> points;
  final Color color;
  final double strokeWidth;

  const ColoredRoad({
    required this.points,
    required this.color,
    this.strokeWidth = 5.0,
  });
}

class AnomalyMarker {
  final LatLng position;
  final String label;
  final Color color;

  const AnomalyMarker({
    required this.position,
    required this.label,
    required this.color,
  });
}

class RoadMapService {
  static const String _overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const double _matchRadius = 25.0;   // metri
  static const double _bboxBuffer  = 0.003;  // ~300 m di buffer intorno alle anomalie

  /// Interroga Overpass API e restituisce strade colorate in base alle anomalie.
  Future<RoadMapData> build(List<Anomaly> anomalies) async {
    if (anomalies.isEmpty) throw Exception('Nessuna anomalia da visualizzare');

    final bbox = _computeBbox(anomalies);
    final ways  = await _fetchRoads(bbox);

    final List<ColoredRoad> roads = [];
    for (final way in ways) {
      final pts = (way['geometry'] as List)
          .map((g) => LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()))
          .toList();
      if (pts.length < 2) continue;

      final severity = _worstSeverityNearWay(pts, anomalies);
      if (severity < 0) continue; // nessuna anomalia vicina → non disegnare

      roads.add(ColoredRoad(
        points: pts,
        color: _severityColor(severity),
        strokeWidth: 6.0,
      ));
    }

    final markers = anomalies.map((a) => AnomalyMarker(
      position: LatLng(a.lat, a.lon),
      label:    a.roadClass,
      color:    _classColor(a.roadClass),
    )).toList();

    final center = LatLng(
      anomalies.map((a) => a.lat).reduce((a, b) => a + b) / anomalies.length,
      anomalies.map((a) => a.lon).reduce((a, b) => a + b) / anomalies.length,
    );

    return RoadMapData(roads: roads, markers: markers, center: center);
  }

  // ── Overpass ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchRoads(
      Map<String, double> bbox) async {
    final query = '''
[out:json][timeout:25];
way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|service|living_street)\$"]
  (${bbox['south']},${bbox['west']},${bbox['north']},${bbox['east']});
out geom;
''';

    final response = await http.post(
      Uri.parse(_overpassUrl),
      body: {'data': query},
    );

    if (response.statusCode != 200) {
      throw Exception('Overpass API error ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    return (decoded['elements'] as List)
        .whereType<Map<String, dynamic>>()
        .where((e) => e['type'] == 'way' && e['geometry'] != null)
        .toList();
  }

  Map<String, double> _computeBbox(List<Anomaly> anomalies) {
    double minLat = anomalies.first.lat, maxLat = anomalies.first.lat;
    double minLon = anomalies.first.lon, maxLon = anomalies.first.lon;
    for (final a in anomalies) {
      if (a.lat < minLat) minLat = a.lat;
      if (a.lat > maxLat) maxLat = a.lat;
      if (a.lon < minLon) minLon = a.lon;
      if (a.lon > maxLon) maxLon = a.lon;
    }
    return {
      'south': minLat - _bboxBuffer,
      'west':  minLon - _bboxBuffer,
      'north': maxLat + _bboxBuffer,
      'east':  maxLon + _bboxBuffer,
    };
  }

  // ── Matching anomalia ↔ strada ────────────────────────────────────────────

  /// Restituisce la severità peggiore tra tutte le anomalie entro _matchRadius
  /// da almeno un segmento della strada. -1 se nessuna.
  int _worstSeverityNearWay(List<LatLng> pts, List<Anomaly> anomalies) {
    int worst = -1;
    for (final a in anomalies) {
      for (int i = 0; i < pts.length - 1; i++) {
        final d = _distanceToSegment(
          LatLng(a.lat, a.lon), pts[i], pts[i + 1]);
        if (d <= _matchRadius) {
          final s = _severity(a.roadClass);
          if (s > worst) worst = s;
          break;
        }
      }
    }
    return worst;
  }

  /// Distanza in metri da punto P al segmento AB (proiezione locale).
  double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    const double degToM = 111320.0;
    final double cosLat = cos(a.latitude * pi / 180.0);

    final double px = (p.longitude - a.longitude) * degToM * cosLat;
    final double py = (p.latitude  - a.latitude)  * degToM;
    final double bx = (b.longitude - a.longitude) * degToM * cosLat;
    final double by = (b.latitude  - a.latitude)  * degToM;

    final double lenSq = bx * bx + by * by;
    if (lenSq == 0) return sqrt(px * px + py * py);

    final double t = max(0.0, min(1.0, (px * bx + py * by) / lenSq));
    final double dx = px - t * bx;
    final double dy = py - t * by;
    return sqrt(dx * dx + dy * dy);
  }

  // ── Colori ────────────────────────────────────────────────────────────────

  int _severity(String roadClass) {
    switch (roadClass) {
      case 'pothole':      return 3;
      case 'metal_bump':   return 2;
      case 'asphalt_bump': return 2;
      case 'worn_road':    return 1;
      default:             return 0;
    }
  }

  Color _severityColor(int severity) {
    switch (severity) {
      case 0:  return Colors.green;
      case 1:  return Colors.yellow.shade700;
      case 2:  return Colors.orange;
      case 3:  return Colors.red;
      default: return Colors.grey;
    }
  }

  Color _classColor(String roadClass) => _severityColor(_severity(roadClass));
}
