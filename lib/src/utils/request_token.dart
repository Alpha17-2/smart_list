/// Monotonically increasing token used to detect superseded requests.
///
/// The controller increments [current] every time a new top-level operation
/// begins (initial load, refresh, search, filter change). In-flight handlers
/// capture the token at start and discard their results if `current` has
/// moved past them — preventing race conditions where an old slow response
/// would otherwise overwrite a newer one.
class RequestToken {
  int _value = 0;

  /// The latest issued token.
  int get current => _value;

  /// Allocate a new token, supersede everything before it, and return it.
  int issue() => ++_value;

  /// `true` if [token] is still the active one.
  bool isCurrent(int token) => token == _value;
}
