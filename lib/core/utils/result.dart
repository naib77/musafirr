import 'package:flutter/foundation.dart';

/// Generic result type for operations that can fail
/// Provides a type-safe way to handle success and failure cases
@immutable
sealed class Result<T, E> {
  const Result();

  /// Returns true if this is a success result
  bool get isSuccess => this is Success<T, E>;

  /// Returns true if this is a failure result
  bool get isFailure => this is Failure<T, E>;

  /// Get the success value or null
  T? get valueOrNull {
    if (this is Success<T, E>) {
      return (this as Success<T, E>).value;
    }
    return null;
  }

  /// Get the error or null
  E? get errorOrNull {
    if (this is Failure<T, E>) {
      return (this as Failure<T, E>).error;
    }
    return null;
  }

  /// Transform the success value
  Result<U, E> map<U>(U Function(T value) transform) {
    if (this is Success<T, E>) {
      return Success(transform((this as Success<T, E>).value));
    }
    return Failure((this as Failure<T, E>).error);
  }

  /// Transform the error
  Result<T, F> mapError<F>(F Function(E error) transform) {
    if (this is Failure<T, E>) {
      return Failure(transform((this as Failure<T, E>).error));
    }
    return Success((this as Success<T, E>).value);
  }

  /// Flat map the success value
  Result<U, E> flatMap<U>(Result<U, E> Function(T value) transform) {
    if (this is Success<T, E>) {
      return transform((this as Success<T, E>).value);
    }
    return Failure((this as Failure<T, E>).error);
  }

  /// Get value or default
  T getOrElse(T defaultValue) {
    if (this is Success<T, E>) {
      return (this as Success<T, E>).value;
    }
    return defaultValue;
  }

  /// Get value or compute default
  T getOrElseCompute(T Function(E error) compute) {
    if (this is Success<T, E>) {
      return (this as Success<T, E>).value;
    }
    return compute((this as Failure<T, E>).error);
  }

  /// Fold the result into a single value
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(E error) onFailure,
  }) {
    if (this is Success<T, E>) {
      return onSuccess((this as Success<T, E>).value);
    }
    return onFailure((this as Failure<T, E>).error);
  }

  /// Execute side effect on success
  Result<T, E> onSuccess(void Function(T value) action) {
    if (this is Success<T, E>) {
      action((this as Success<T, E>).value);
    }
    return this;
  }

  /// Execute side effect on failure
  Result<T, E> onFailure(void Function(E error) action) {
    if (this is Failure<T, E>) {
      action((this as Failure<T, E>).error);
    }
    return this;
  }
}

/// Success result
@immutable
final class Success<T, E> extends Result<T, E> {
  const Success(this.value);
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T, E> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// Failure result
@immutable
final class Failure<T, E> extends Result<T, E> {
  const Failure(this.error);
  final E error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T, E> &&
          runtimeType == other.runtimeType &&
          error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Failure($error)';
}

/// Standard app error for use with Result
@immutable
class AppError {
  const AppError({
    required this.message,
    this.code,
    this.details,
    this.stackTrace,
    this.isRetryable = false,
  });

  final String message;
  final String? code;
  final dynamic details;
  final StackTrace? stackTrace;
  final bool isRetryable;

  /// Common error types
  factory AppError.network({String? message}) => AppError(
        message: message ?? 'Network error. Please check your connection.',
        code: 'NETWORK_ERROR',
        isRetryable: true,
      );

  factory AppError.timeout({String? message}) => AppError(
        message: message ?? 'Request timed out. Please try again.',
        code: 'TIMEOUT',
        isRetryable: true,
      );

  factory AppError.server({String? message, String? code}) => AppError(
        message: message ?? 'Server error. Please try again later.',
        code: code ?? 'SERVER_ERROR',
        isRetryable: true,
      );

  factory AppError.unauthorized({String? message}) => AppError(
        message: message ?? 'Please log in to continue.',
        code: 'UNAUTHORIZED',
        isRetryable: false,
      );

  factory AppError.forbidden({String? message}) => AppError(
        message: message ?? 'You don\'t have permission to do this.',
        code: 'FORBIDDEN',
        isRetryable: false,
      );

  factory AppError.notFound({String? message}) => AppError(
        message: message ?? 'The requested resource was not found.',
        code: 'NOT_FOUND',
        isRetryable: false,
      );

  factory AppError.validation({required String message, String? code}) =>
      AppError(
        message: message,
        code: code ?? 'VALIDATION_ERROR',
        isRetryable: false,
      );

  factory AppError.unknown({String? message, dynamic details, StackTrace? stackTrace}) =>
      AppError(
        message: message ?? 'An unexpected error occurred.',
        code: 'UNKNOWN_ERROR',
        details: details,
        stackTrace: stackTrace,
        isRetryable: true,
      );

  @override
  String toString() => 'AppError($code: $message)';
}

/// Type alias for common Result patterns
typedef AppResult<T> = Result<T, AppError>;

/// Extension for async Result operations
extension ResultFuture<T, E> on Future<Result<T, E>> {
  /// Map success value asynchronously
  Future<Result<U, E>> mapAsync<U>(Future<U> Function(T value) transform) async {
    final result = await this;
    if (result is Success<T, E>) {
      return Success(await transform(result.value));
    }
    return Failure((result as Failure<T, E>).error);
  }

  /// Flat map success value asynchronously
  Future<Result<U, E>> flatMapAsync<U>(
      Future<Result<U, E>> Function(T value) transform) async {
    final result = await this;
    if (result is Success<T, E>) {
      return await transform(result.value);
    }
    return Failure((result as Failure<T, E>).error);
  }
}

/// Helper to run an operation and wrap exceptions in Result
Future<AppResult<T>> runCatching<T>(Future<T> Function() operation) async {
  try {
    return Success(await operation());
  } catch (e, stackTrace) {
    return Failure(AppError.unknown(
      message: e.toString(),
      details: e,
      stackTrace: stackTrace,
    ));
  }
}

/// Helper to run a sync operation and wrap exceptions in Result
AppResult<T> runCatchingSync<T>(T Function() operation) {
  try {
    return Success(operation());
  } catch (e, stackTrace) {
    return Failure(AppError.unknown(
      message: e.toString(),
      details: e,
      stackTrace: stackTrace,
    ));
  }
}
