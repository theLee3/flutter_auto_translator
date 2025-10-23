/// {@template translator}
/// Signals that work is being done in terminal, i.e. when waiting for a
/// response from a translation service.
/// {@endtemplate}
class Spinner {
  /// Signals that work is being done in terminal, i.e. when waiting for a
  /// response from a translation service.
  const Spinner(int ticks) : _index = ticks % 10;

  final int _index;
  final _segments = const ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

  @override
  String toString() => _segments[_index];
}
