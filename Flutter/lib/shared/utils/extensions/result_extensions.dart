import 'package:justus/all_imports.dart';

extension ResultWrapperExtensions<T> on ResultWrapper<T> {
  bool get isSuccess => this is Success<T>;
  bool get isError => this is GenericError<T> || this is NetworkError<T>;

  T? get valueOrNull =>
      (this is Success<T>) ? (this as Success<T>).value : null;

  ResultWrapper<R> map<R>(R Function(T value) transform) {
    switch (this) {
      case Success<T>(:final value):
        try {
          return Success(transform(value));
        } catch (e) {
          return GenericError<R>(message: e.toString());
        }
      case GenericError<T>(:final code, :final message, :final details):
        return GenericError<R>(code: code, message: message, details: details);
      case NetworkError<T>(:final message):
        return NetworkError<R>(message: message);
    }
  }

  void handle({
    required void Function(T value) onSuccess,
    void Function(int? code, String? message)? onError,
    void Function()? onNetworkError,
  }) {
    switch (this) {
      case Success<T>(:final value):
        onSuccess(value);
      case GenericError<T>(:final code, :final message):
        if (onError != null) {
          onError(code, message);
        } else {
          ErrorHandler.handle(this);
        }
      case NetworkError<T>():
        if (onNetworkError != null) {
          onNetworkError();
        } else {
          ErrorHandler.handle(AppError.network());
        }
    }
  }

  Future<void> handleAsync({
    required Future<void> Function(T value) onSuccess,
    void Function(int? code, String? message)? onError,
    void Function()? onNetworkError,
  }) async {
    switch (this) {
      case Success<T>(:final value):
        await onSuccess(value);
      case GenericError<T>(:final code, :final message):
        if (onError != null) {
          onError(code, message);
        } else {
          ErrorHandler.handle(this);
        }
      case NetworkError<T>():
        if (onNetworkError != null) {
          onNetworkError();
        } else {
          ErrorHandler.handle(AppError.network());
        }
    }
  }
}
