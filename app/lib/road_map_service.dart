import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'anomaly.dart';

/// Risultato del servizio mappa: strade colorate + marker anomalie.
class RoadMapData {
  final List<ColoredRoad>   roads;
  final List<AnomalyMarker> markers;
  final LatLng              center;

  const RoadMapData({
    required this.roads,
    required this.markers,
    required this.center,
  });
}

class ColoredRoad {
  final List<LatLng> points;
  final Color        color;
  final double       strokeWidth;

  const ColoredRoad({
    required this.points,
    required this.color,
    this.strokeWidth = 5.0,
  });
}

class AnomalyMarker {
  final LatLng position;
  final String label;
  final Color  color;

  const AnomalyMarker({
    required this.position,
    required this.label,
    required this.color,
  });
}

class RoadMapService {
  static final RoadMapService _instance = RoadMapService._();
  factory RoadMapService() => _instance;
  RoadMapService._();

  static const String _osrmUrl           = 'https://router.project-osrm.org/match/v1/driving';
  static const int    _maxTracePoints     = 100;   // cap per URL length
  static const double _hotspotRadiusM     = 50.0;  // raggio entro cui colorare il percorso

  /// Costruisce la mappa: map matching via OSRM + overlay anomalie.
  ///
  /// [tracePoints] e [traceTimestamps] devono avere la stessa lunghezza.
  /// Se la traccia è vuota, vengono mostrati solo i marker senza percorso.
  Future<RoadMapData> build(
    List<Anomaly> anomalies,
    List<LatLng>  tracePoints,
    List<int>     traceTimestamps,
  ) async {
    final valid = anomalies.where(_hasValidGps).toList();
    if (valid.isEmpty) throw Exception('Nessuna anomalia con coordinate GPS valide');

    List<LatLng> route = [];
    if (tracePoints.length >= 2) {
      route = await _matchRoute(tracePoints, traceTimestamps);
    }

    final roads = <ColoredRoad>[];

    if (route.isNotEmpty) {
      // Percorso base grigio
      roads.add(ColoredRoad(
        points:      route,
        color:       Colors.blueGrey.shade400,
        strokeWidth: 4.0,
      ));

      // Hotspot colorati vicino a ogni anomalia
      for (final a in valid) {
        final idx = _nearestRouteIndex(LatLng(a.lat, a.lon), route);
        if (idx < 0) continue;
        final start = (idx - 4).clamp(0, route.length - 1);
        final end   = (idx + 4).clamp(0, route.length - 1);
        if (start >= end) continue;
        roads.add(ColoredRoad(
          points:      route.sublist(start, end + 1),
          color:       _classColor(a.roadClass),
          strokeWidth: 8.0,
        ));
      }
    }

    final markers = valid.map((a) => AnomalyMarker(
      position: LatLng(a.lat, a.lon),
      label:    a.roadClass,
      color:    _classColor(a.roadClass),
    )).toList();

    final center = route.isNotEmpty
        ? route[route.length ~/ 2]
        : LatLng(
            valid.map((a) => a.lat).reduce((a, b) => a + b) / valid.length,
            valid.map((a) => a.lon).reduce((a, b) => a + b) / valid.length,
          );

    return RoadMapData(roads: roads, markers: markers, center: center);
  }

  // ── OSRM Match ────────────────────────────────────────────────────────────

  Future<List<LatLng>> _matchRoute(
      List<LatLng> points, List<int> timestamps) async {
    final (pts, ts) = _downsample(points, timestamps, _maxTracePoints);

    final coords = pts
        .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
        .join(';');
    final tsParam = ts.join(';');

    final uri = Uri.parse(
      '$_osrmUrl/$coords?geometries=geojson&overview=full&timestamps=$tsParam',
    );

    late http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('Errore di rete OSRM: $e');
    }

    if (response.statusCode != 200) {
      throw Exception('OSRM error ${response.statusCode}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final code    = decoded['code'] as String;

    if (code == 'NoMatch') {
      throw Exception(
        'Nessuna strada trovata per il tracciato GPS. '
        'Assicurati di aver guidato su strade mappate con GPS attivo.',
      );
    }
    if (code != 'Ok') {
      throw Exception('OSRM: ${decoded['message'] ?? code}');
    }

    // Concatena tutti i matching (OSRM può spezzarli in caso di gap GPS)
    final matchings = decoded['matchings'] as List;
    final List<LatLng> route = [];
    for (final m in matchings) {
      for (final c in m['geometry']['coordinates'] as List) {
        // GeoJSON: [longitude, latitude]
        route.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
      }
    }
    return route;
  }

  /// Riduce la traccia a [maxCount] punti campionando uniformemente.
  (List<LatLng>, List<int>) _downsample(
      List<LatLng> pts, List<int> ts, int maxCount) {
    if (pts.length <= maxCount) return (pts, ts);
    final step = (pts.length / maxCount).ceil();
    final outPts = <LatLng>[];
    final outTs  = <int>[];
    for (int i = 0; i < pts.length; i += step) {
      outPts.add(pts[i]);
      outTs.add(ts[i]);
    }
    if (outPts.last != pts.last) {
      outPts.add(pts.last);
      outTs.add(ts.last);
    }
    return (outPts, outTs);
  }

  // ── Geometria ─────────────────────────────────────────────────────────────

  /// Indice del punto del percorso più vicino a [point] entro [_hotspotRadiusM],
  /// oppure -1 se nessun punto è abbastanza vicino.
  int _nearestRouteIndex(LatLng point, List<LatLng> route) {
    int nearest = -1;
    double minDist = _hotspotRadiusM;
    for (int i = 0; i < route.length; i++) {
      final d = _distanceBetween(point, route[i]);
      if (d < minDist) { minDist = d; nearest = i; }
    }
    return nearest;
  }

  double _distanceBetween(LatLng a, LatLng b) {
    const degToM = 111320.0;
    final cosLat = cos(a.latitude * pi / 180.0);
    final dx = (a.longitude - b.longitude) * degToM * cosLat;
    final dy = (a.latitude  - b.latitude)  * degToM;
    return sqrt(dx * dx + dy * dy);
  }

  // ── Validazione GPS ───────────────────────────────────────────────────────

  bool _hasValidGps(Anomaly a) =>
      a.lat.isFinite && a.lon.isFinite &&
      a.lat >= -90  && a.lat <= 90 &&
      a.lon >= -180 && a.lon <= 180;

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
      case 1:  return Colors.yellow.shade700;
      case 2:  return Colors.orange;
      case 3:  return Colors.red;
      default: return Colors.green;
    }
  }

  Color _classColor(String roadClass) => _severityColor(_severity(roadClass));
}
