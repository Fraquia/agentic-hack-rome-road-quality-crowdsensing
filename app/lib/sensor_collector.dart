import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

/// Raccoglie campioni dall'accelerometro a ~50 Hz e li accumula
/// in un buffer circolare. Ogni volta che sono disponibili [step]
/// nuovi campioni emette una finestra ordinata di [windowSize] valori.
///
/// IMPORTANTE: windowSize deve coincidere con il WINDOW_SIZE usato in training.
class SensorCollector {
  static const int windowSize = 200;   // campioni (4 s a 50 Hz)
  static const int step       = 100;   // overlap 50%

  static const Duration _sampleInterval = Duration(milliseconds: 20); // 50 Hz

  final _buffer = List<double>.filled(windowSize, 0.0);
  int _cursor      = 0;
  int _sampleCount = 0;

  DateTime _lastSampleTime = DateTime.fromMillisecondsSinceEpoch(0);

  final _windowController = StreamController<List<double>>.broadcast();

  /// Stream di finestre pronte per l'inferenza.
  Stream<List<double>> get windows => _windowController.stream;

  StreamSubscription<AccelerometerEvent>? _subscription;

  void start() {
    _subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onEvent);
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _windowController.close();
  }

  void _onEvent(AccelerometerEvent event) {
    final now = DateTime.now();
    if (now.difference(_lastSampleTime) < _sampleInterval) return;
    _lastSampleTime = now;
    onAccelerometerEvent(event.z);
  }

  void onAccelerometerEvent(double zValue) {
    _buffer[_cursor % windowSize] = zValue;
    _cursor++;
    _sampleCount++;

    if (_sampleCount >= windowSize && _sampleCount % step == 0) {
      _windowController.add(_getOrderedWindow());
    }
  }

  List<double> _getOrderedWindow() {
    final start = _cursor % windowSize;
    return [
      ..._buffer.sublist(start),
      ..._buffer.sublist(0, start),
    ];
  }
}
