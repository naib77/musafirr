import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Retry configuration
class RetryConfig {
  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitterFactor = 0.1,
    this.retryIf,
  });

  /// Maximum number of retry attempts
  final int maxAttempts;

  /// Initial delay before first retry
  final Duration initialDelay;

  /// Maximum delay between retries
  final Duration maxDelay;

  /// Multiplier for exponential backoff
  final double backoffMultiplier;

  /// Random jitter factor (0.0 to 1.0) to prevent thundering herd
  final double jitterFactor;

  /// Custom function to determine if an error should trigger a retry
  final bool Function(Object error)? retryIf;

  /// Calculate delay for a given attempt number
  Duration getDelayForAttempt(int attempt) {
    final exponentialDelay = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attempt - 1).toInt();

    final clampedDelay = min(exponentialDelay, maxDelay.inMilliseconds);

    // Add jitter
    final jitter =
        (Random().nextDouble() * 2 - 1) * jitterFactor * clampedDelay;
    final finalDelay = (clampedDelay + jitter).round();

    return Duration(milliseconds: max(0, finalDelay));
  }

  /// Check if an error should be retried
  bool shouldRetry(Object error) {
    if (retryIf != null) {
      return retryIf!(error);
    }
    // Default: retry on timeout and network errors
    return _isRetryableError(error);
  }

  static bool _isRetryableError(Object error) {
    final errorString = error.toString().toLowerCase();
    return errorString.contains('timeout') ||
        errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('host');
  }
}

/// Retry result with attempt information
class RetryResult<T> {
  const RetryResult({
    required this.value,
    required this.attempts,
    required this.totalDuration,
  });

  final T value;
  final int attempts;
  final Duration totalDuration;
}

/// Retry with exponential backoff
Future<T> retry<T>(
  Future<T> Function() operation, {
  RetryConfig config = const RetryConfig(),
  void Function(int attempt, Object error, Duration nextDelay)? onRetry,
}) async {
  final stopwatch = Stopwatch()..start();
  int attempt = 0;
  Object? lastError;
  StackTrace? lastStackTrace;

  while (attempt < config.maxAttempts) {
    attempt++;
    try {
      return await operation();
    } catch (e, st) {
      lastError = e;
      lastStackTrace = st;

      if (attempt >= config.maxAttempts || !config.shouldRetry(e)) {
        break;
      }

      final delay = config.getDelayForAttempt(attempt);

      if (kDebugMode) {
        debugPrint('⚠️ Retry attempt $attempt failed: $e');
        debugPrint('   Retrying in ${delay.inMilliseconds}ms...');
      }

      onRetry?.call(attempt, e, delay);
      await Future.delayed(delay);
    }
  }

  stopwatch.stop();
  if (kDebugMode) {
    debugPrint(
        '❌ All $attempt retry attempts failed after ${stopwatch.elapsed.inMilliseconds}ms');
  }

  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}

/// Retry with result information
Future<RetryResult<T>> retryWithResult<T>(
  Future<T> Function() operation, {
  RetryConfig config = const RetryConfig(),
  void Function(int attempt, Object error, Duration nextDelay)? onRetry,
}) async {
  final stopwatch = Stopwatch()..start();
  final result = await retry(
    operation,
    config: config,
    onRetry: onRetry,
  );
  stopwatch.stop();

  return RetryResult(
    value: result,
    attempts: 1, // Will be updated by retry function
    totalDuration: stopwatch.elapsed,
  );
}

/// Circuit breaker states
enum CircuitState { closed, open, halfOpen }

/// Circuit breaker for preventing cascading failures
class CircuitBreaker {
  CircuitBreaker({
    this.failureThreshold = 5,
    this.successThreshold = 2,
    this.timeout = const Duration(seconds: 30),
    this.onStateChange,
  });

  /// Number of failures before opening circuit
  final int failureThreshold;

  /// Number of successes in half-open state before closing
  final int successThreshold;

  /// Time to wait before transitioning from open to half-open
  final Duration timeout;

  /// Callback when state changes
  final void Function(CircuitState oldState, CircuitState newState)?
      onStateChange;

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastFailureTime;

  /// Current circuit state
  CircuitState get state => _state;

  /// Check if circuit allows requests
  bool get isAllowed {
    _checkStateTransition();
    return _state != CircuitState.open;
  }

  void _checkStateTransition() {
    if (_state == CircuitState.open && _lastFailureTime != null) {
      final elapsed = DateTime.now().difference(_lastFailureTime!);
      if (elapsed >= timeout) {
        _transitionTo(CircuitState.halfOpen);
      }
    }
  }

  void _transitionTo(CircuitState newState) {
    if (_state != newState) {
      final oldState = _state;
      _state = newState;

      if (newState == CircuitState.closed) {
        _failureCount = 0;
        _successCount = 0;
      } else if (newState == CircuitState.halfOpen) {
        _successCount = 0;
      }

      if (kDebugMode) {
        debugPrint('🔌 Circuit breaker: $oldState → $newState');
      }

      onStateChange?.call(oldState, newState);
    }
  }

  /// Record a successful operation
  void recordSuccess() {
    if (_state == CircuitState.halfOpen) {
      _successCount++;
      if (_successCount >= successThreshold) {
        _transitionTo(CircuitState.closed);
      }
    } else if (_state == CircuitState.closed) {
      _failureCount = 0; // Reset failures on success
    }
  }

  /// Record a failed operation
  void recordFailure() {
    _lastFailureTime = DateTime.now();

    if (_state == CircuitState.halfOpen) {
      _transitionTo(CircuitState.open);
    } else if (_state == CircuitState.closed) {
      _failureCount++;
      if (_failureCount >= failureThreshold) {
        _transitionTo(CircuitState.open);
      }
    }
  }

  /// Execute an operation with circuit breaker protection
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (!isAllowed) {
      throw CircuitBreakerOpenException(
        'Circuit breaker is open. Try again later.',
        timeout: timeout,
        lastFailure: _lastFailureTime,
      );
    }

    try {
      final result = await operation();
      recordSuccess();
      return result;
    } catch (e) {
      recordFailure();
      rethrow;
    }
  }

  /// Reset the circuit breaker
  void reset() {
    _transitionTo(CircuitState.closed);
    _failureCount = 0;
    _successCount = 0;
    _lastFailureTime = null;
  }
}

/// Exception thrown when circuit breaker is open
class CircuitBreakerOpenException implements Exception {
  const CircuitBreakerOpenException(
    this.message, {
    this.timeout,
    this.lastFailure,
  });

  final String message;
  final Duration? timeout;
  final DateTime? lastFailure;

  Duration? get timeUntilRetry {
    if (lastFailure == null || timeout == null) return null;
    final elapsed = DateTime.now().difference(lastFailure!);
    final remaining = timeout! - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}

/// Timeout wrapper with cancellation support
class TimeoutOperation<T> {
  TimeoutOperation({
    required this.operation,
    required this.timeout,
    this.onTimeout,
  });

  final Future<T> Function() operation;
  final Duration timeout;
  final T Function()? onTimeout;

  Future<T> execute() async {
    try {
      return await operation().timeout(timeout);
    } on TimeoutException {
      if (onTimeout != null) {
        return onTimeout!();
      }
      rethrow;
    }
  }
}

/// Bulkhead pattern for isolating failures
class Bulkhead {
  Bulkhead({
    required this.maxConcurrent,
    this.maxQueue = 0,
    this.queueTimeout = const Duration(seconds: 30),
  });

  final int maxConcurrent;
  final int maxQueue;
  final Duration queueTimeout;

  int _activeCount = 0;
  final _queue = <_QueuedOperation>[];

  /// Current number of active operations
  int get activeCount => _activeCount;

  /// Current queue size
  int get queueSize => _queue.length;

  /// Check if can accept new operation
  bool get canAccept =>
      _activeCount < maxConcurrent || _queue.length < maxQueue;

  /// Execute an operation with bulkhead protection
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_activeCount < maxConcurrent) {
      return _executeNow(operation);
    }

    if (maxQueue > 0 && _queue.length < maxQueue) {
      return _queueOperation(operation);
    }

    throw BulkheadRejectedException(
      'Bulkhead is full. Active: $_activeCount, Queue: ${_queue.length}',
    );
  }

  Future<T> _executeNow<T>(Future<T> Function() operation) async {
    _activeCount++;
    try {
      return await operation();
    } finally {
      _activeCount--;
      _processQueue();
    }
  }

  Future<T> _queueOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    final queuedOp = _QueuedOperation(
      execute: () async {
        try {
          final result = await _executeNow(operation);
          completer.complete(result);
        } catch (e, st) {
          completer.completeError(e, st);
        }
      },
      timeout: DateTime.now().add(queueTimeout),
    );

    _queue.add(queuedOp);

    // Set up timeout
    Future.delayed(queueTimeout, () {
      if (_queue.remove(queuedOp) && !completer.isCompleted) {
        completer.completeError(
          BulkheadTimeoutException('Operation timed out waiting in queue'),
        );
      }
    });

    return completer.future;
  }

  void _processQueue() {
    if (_queue.isEmpty || _activeCount >= maxConcurrent) return;

    // Remove timed out operations
    final now = DateTime.now();
    _queue.removeWhere((op) => op.timeout.isBefore(now));

    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      next.execute();
    }
  }
}

class _QueuedOperation {
  _QueuedOperation({
    required this.execute,
    required this.timeout,
  });

  final Future<void> Function() execute;
  final DateTime timeout;
}

/// Exception thrown when bulkhead rejects an operation
class BulkheadRejectedException implements Exception {
  const BulkheadRejectedException(this.message);
  final String message;

  @override
  String toString() => 'BulkheadRejectedException: $message';
}

/// Exception thrown when operation times out in queue
class BulkheadTimeoutException implements Exception {
  const BulkheadTimeoutException(this.message);
  final String message;

  @override
  String toString() => 'BulkheadTimeoutException: $message';
}

/// Rate limiter using token bucket algorithm
class RateLimiter {
  RateLimiter({
    required this.maxTokens,
    required this.refillRate,
    this.refillInterval = const Duration(seconds: 1),
  }) : _tokens = maxTokens.toDouble() {
    _startRefill();
  }

  final int maxTokens;
  final int refillRate;
  final Duration refillInterval;

  double _tokens;
  Timer? _refillTimer;
  DateTime _lastRefill = DateTime.now();

  /// Current available tokens
  int get availableTokens => _tokens.floor();

  /// Check if a request can proceed
  bool get canProceed => _tokens >= 1;

  void _startRefill() {
    _refillTimer = Timer.periodic(refillInterval, (_) => _refill());
  }

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill);
    final tokensToAdd =
        (elapsed.inMilliseconds / refillInterval.inMilliseconds) * refillRate;

    _tokens = min(_tokens + tokensToAdd, maxTokens.toDouble());
    _lastRefill = now;
  }

  /// Try to consume a token
  bool tryConsume([int tokens = 1]) {
    _refill();
    if (_tokens >= tokens) {
      _tokens -= tokens;
      return true;
    }
    return false;
  }

  /// Wait until a token is available, then consume it
  Future<void> acquire([int tokens = 1]) async {
    while (!tryConsume(tokens)) {
      await Future.delayed(Duration(
        milliseconds: (refillInterval.inMilliseconds / refillRate).ceil(),
      ));
    }
  }

  /// Execute an operation with rate limiting
  Future<T> execute<T>(Future<T> Function() operation) async {
    await acquire();
    return operation();
  }

  /// Dispose the rate limiter
  void dispose() {
    _refillTimer?.cancel();
    _refillTimer = null;
  }
}

/// Exception thrown when rate limit is exceeded
class RateLimitExceededException implements Exception {
  const RateLimitExceededException(this.message, {this.retryAfter});
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => 'RateLimitExceededException: $message';
}

/// Combine multiple resilience patterns
class ResilientOperation<T> {
  ResilientOperation({
    required this.operation,
    this.retryConfig,
    this.circuitBreaker,
    this.bulkhead,
    this.rateLimiter,
    this.timeout,
  });

  final Future<T> Function() operation;
  final RetryConfig? retryConfig;
  final CircuitBreaker? circuitBreaker;
  final Bulkhead? bulkhead;
  final RateLimiter? rateLimiter;
  final Duration? timeout;

  /// Execute the operation with all configured resilience patterns
  Future<T> execute() async {
    Future<T> op = operation();

    // Apply timeout
    if (timeout != null) {
      op = op.timeout(timeout!);
    }

    // Wrap with rate limiter
    Future<T> Function() wrappedOp = () => op;

    if (rateLimiter != null) {
      final innerOp = wrappedOp;
      wrappedOp = () => rateLimiter!.execute(innerOp);
    }

    // Wrap with bulkhead
    if (bulkhead != null) {
      final innerOp = wrappedOp;
      wrappedOp = () => bulkhead!.execute(innerOp);
    }

    // Wrap with circuit breaker
    if (circuitBreaker != null) {
      final innerOp = wrappedOp;
      wrappedOp = () => circuitBreaker!.execute(innerOp);
    }

    // Wrap with retry
    if (retryConfig != null) {
      return retry(wrappedOp, config: retryConfig!);
    }

    return wrappedOp();
  }
}
