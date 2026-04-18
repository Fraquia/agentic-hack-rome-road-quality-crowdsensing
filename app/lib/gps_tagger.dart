import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'anomaly.dart';

enum GpsStatus { unavailable, acquiring, ready }

// TODO(server): impostare a true e implementare _uploadBatch() quando
// il backend è disponibile. Richiede: endpoint URL, package http,
// SharedPreferences per retry offline.
const bool _serverEnabled = false;

/// Gestisce il campionamento GPS e la registrazione della traccia di percorso.
class GpsTagger {
  static const double   _maxAccuracyMeters = 50.0;
  static const Duration _traceInterval     = Duration(seconds: 5);

  Position?  _lastPosition;
  GpsStatus  _status = GpsStatus.unavailable;

  // Traccia del percorso: un punto ogni _traceInterval secondi.
  final List<LatLng> _tracePoints     = [];
  final List<int>    _traceTimestamps = []; // Unix epoch seconds
  DateTime           _lastTraceTime   = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<Position>? _gpsSub;
  final _statusController = StreamController<GpsStatus>.broadcast();

  Position?  get lastPosition     => _lastPosition;
  GpsStatus  get status           => _status;
  List<LatLng> get tracePoints    => List.unmodifiable(_tracePoints);
  List<int>    get traceTimestamps => List.unmodifiable(_traceTimestamps);

  /// Emette il nuovo stato ogni volta che cambia.
  Stream<GpsStatus> get statusStream => _statusController.stream;

  Future<void> start() async {
    // Nuova sessione: azzera la traccia precedente.
    _tracePoints.clear();
    _traceTimestamps.clear();
    _lastTraceTime = DateTime.fromMillisecondsSinceEpoch(0);

    _setStatus(GpsStatus.acquiring);

    if (!await _ensurePermission()) {
      _setStatus(GpsStatus.unavailable);
      return;
    }

    // Posizione nota immediata per ridurre la finestra senza GPS a inizio sessione.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && last.accuracy <= _maxAccuracyMeters) {
        _lastPosition = last;
        _setStatus(GpsStatus.ready);
      }
    } catch (_) {}

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      if (pos.accuracy <= _maxAccuracyMeters) {
        _lastPosition = pos;
        if (_status != GpsStatus.ready) _setStatus(GpsStatus.ready);

        // Registra un punto della traccia ogni _traceInterval.
        final now = DateTime.now();
        if (now.difference(_lastTraceTime) >= _traceInterval) {
          _tracePoints.add(LatLng(pos.latitude, pos.longitude));
          _traceTimestamps.add(now.millisecondsSinceEpoch ~/ 1000);
          _lastTraceTime = now;
        }
      }
    });
  }

  void stop() {
    _gpsSub?.cancel();
    _gpsSub = null;
  }

  void dispose() {
    stop();
    _statusController.close();
  }

  /// No-op in modalità locale. Quando _serverEnabled = true, implementare
  /// upload batch e persistenza offline per retry.
  Future<void> flush(List<Anomaly> anomalies) async {
    if (!_serverEnabled) return;
    // ignore: dead_code
    // TODO(server): await _uploadBatch(anomalies);
  }

  void _setStatus(GpsStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  Future<bool> _ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm != LocationPermission.denied &&
        perm != LocationPermission.deniedForever;
  }
}
