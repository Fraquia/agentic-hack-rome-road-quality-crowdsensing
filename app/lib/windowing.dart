/// Post-processing temporale con majority vote sulle ultime 3 inferenze.
///
/// Le buche durano 200–500 ms, meno di una finestra da 2 s.
/// Segnala un'anomalia solo se almeno 2 delle ultime 3 predizioni
/// concordano sulla stessa classe non-smooth.
class WindowingVoter {
  static const int _historySize = 3;
  static const int _minAgreement = 2;
  static const String _smoothClass = 'smooth';

  final List<String> _history = [];

  /// Aggiunge una predizione e restituisce la classe confermata
  /// se c'è accordo su un'anomalia, altrimenti null.
  String? confirm(String prediction) {
    _history.add(prediction);
    if (_history.length > _historySize) {
      _history.removeAt(0);
    }

    if (_history.length < _historySize) return null;

    // Conta le occorrenze di ogni classe non-smooth
    final counts = <String, int>{};
    for (final label in _history) {
      if (label != _smoothClass) {
        counts[label] = (counts[label] ?? 0) + 1;
      }
    }

    // Trova la classe con più voti
    String? bestClass;
    int bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        bestClass = entry.key;
      }
    }

    if (bestClass != null && bestCount >= _minAgreement) {
      return bestClass;
    }
    return null;
  }

  /// Resetta il buffer storico (es. all'inizio di una nuova sessione).
  void reset() => _history.clear();
}
