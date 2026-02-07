// =============================================================================
// ResultWrapper - Error handling wrapper for API calls
// Dart equivalent of ResultWrapper.kt
// =============================================================================

sealed class ResultWrapper<T> {
  const ResultWrapper();
}

class Success<T> extends ResultWrapper<T> {
  final T value;
  const Success(this.value);
}

class GenericError<T> extends ResultWrapper<T> {
  final int? code;
  final String? message;
  const GenericError({this.code, this.message});
}

class NetworkError<T> extends ResultWrapper<T> {
  const NetworkError();
}
