import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'anomaly.dart';

// TODO: sostituire con il reale endpoint del server prima del demo
const String _serverUrl = 'https://your-server.example.com/api/anomalies';

/// Gestisce il campionamento GPS e l'upload batch al server.
class GpsTagger {
  static const Duration _flushInterval = Duration(minutes: 5);

  Position? _lastPosition;

  StreamSubscription<Position>? _gpsSub;
  Timer? _flushTimer;

  Position? get lastPosition => _lastPosition;

  /// Avvia il campionamento GPS.
  Future<void> start() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((pos) => _lastPosition = pos);

    _flushTimer = Timer.periodic(
      _flushInterval,
      (_) => flush(const []),
    );
  }

  /// Ferma il campionamento GPS.
  void stop() {
    _gpsSub?.cancel();
    _flushTimer?.cancel();
  }

  /// Invia le anomalie passate al server in batch.
  Future<void> flush(List<Anomaly> anomalies) async {
    if (anomalies.isEmpty) return;
    try {
      final body = json.encode({
        'anomalies': anomalies.map((a) => a.toJson()).toList(),
      });
      await http.post(
        Uri.parse(_serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (_) {
      // Upload fallito: i dati rimangono in AnomalyStore fino al prossimo flush
    }
  }
}
