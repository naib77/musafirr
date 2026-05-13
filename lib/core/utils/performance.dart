import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Performance monitoring utilities
class PerformanceMonitor {
  PerformanceMonitor._();

  static final _instance = PerformanceMonitor._();
  static PerformanceMonitor get instance => _instance;

  final _metrics = <String, List<Duration>>{};
  final _traces = <String, _Trace>{};
  bool _isEnabled = kDebugMode;

  /// Enable or disable performance monitoring
  set isEnabled(bool value) => _isEnabled = value;
  bool get isEnabled => _isEnabled;

  /// Start a trace
  void startTrace(String name) {
    if (!_isEnabled) return;
    _traces[name] = _Trace(name: name, startTime: DateTime.now());
  }

  /// Stop a trace and record the duration
  Duration? stopTrace(String name) {
    if (!_isEnabled) return null;

    final trace = _traces.remove(name);
    if (trace == null) return null;

    final duration = DateTime.now().difference(trace.startTime);
    _recordMetric(name, duration);
    return duration;
  }

  /// Measure an async operation
  Future<T> measureAsync<T>(String name, Future<T> Function() operation) async {
    if (!_isEnabled) return operation();

    startTrace(name);
    try {
      return await operation();
    } finally {
      stopTrace(name);
    }
  }

  /// Measure a sync operation
  T measureSync<T>(String name, T Function() operation) {
    if (!_isEnabled) return operation();

    startTrace(name);
    try {
      return operation();
    } finally {
      stopTrace(name);
    }
  }

  void _recordMetric(String name, Duration duration) {
    _metrics.putIfAbsent(name, () => []);
    _metrics[name]!.add(duration);

    // Keep only last 100 measurements
    if (_metrics[name]!.length > 100) {
      _metrics[name]!.removeAt(0);
    }

    if (kDebugMode) {
      print('⏱️ [$name] ${duration.inMilliseconds}ms');
    }
  }

  /// Get average duration for a metric
  Duration? getAverageDuration(String name) {
    final durations = _metrics[name];
    if (durations == null || durations.isEmpty) return null;

    final totalMs = durations.fold<int>(
      0,
      (sum, d) => sum + d.inMilliseconds,
    );
    return Duration(milliseconds: totalMs ~/ durations.length);
  }

  /// Get all metrics
  Map<String, _MetricSummary> getAllMetrics() {
    return _metrics.map((name, durations) {
      if (durations.isEmpty) {
        return MapEntry(name, _MetricSummary.empty(name));
      }

      final sorted = List<Duration>.from(durations)
        ..sort((a, b) => a.compareTo(b));

      return MapEntry(
        name,
        _MetricSummary(
          name: name,
          count: durations.length,
          min: sorted.first,
          max: sorted.last,
          average: Duration(
            milliseconds: durations.fold<int>(
                  0,
                  (sum, d) => sum + d.inMilliseconds,
                ) ~/
                durations.length,
          ),
          p50: sorted[sorted.length ~/ 2],
          p95: sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)],
        ),
      );
    });
  }

  /// Clear all metrics
  void clearMetrics() {
    _metrics.clear();
    _traces.clear();
  }

  /// Print all metrics to console
  void printMetrics() {
    if (!kDebugMode) return;

    print('═══════════════════════════════════════════════════════');
    print('                  PERFORMANCE METRICS                   ');
    print('═══════════════════════════════════════════════════════');

    final metrics = getAllMetrics();
    for (final entry in metrics.entries) {
      final m = entry.value;
      print('📊 ${m.name}:');
      print('   Count: ${m.count}');
      print('   Min: ${m.min.inMilliseconds}ms');
      print('   Max: ${m.max.inMilliseconds}ms');
      print('   Avg: ${m.average.inMilliseconds}ms');
      print('   P50: ${m.p50.inMilliseconds}ms');
      print('   P95: ${m.p95.inMilliseconds}ms');
      print('───────────────────────────────────────────────────────');
    }
  }
}

class _Trace {
  const _Trace({required this.name, required this.startTime});
  final String name;
  final DateTime startTime;
}

class _MetricSummary {
  const _MetricSummary({
    required this.name,
    required this.count,
    required this.min,
    required this.max,
    required this.average,
    required this.p50,
    required this.p95,
  });

  factory _MetricSummary.empty(String name) => _MetricSummary(
        name: name,
        count: 0,
        min: Duration.zero,
        max: Duration.zero,
        average: Duration.zero,
        p50: Duration.zero,
        p95: Duration.zero,
      );

  final String name;
  final int count;
  final Duration min;
  final Duration max;
  final Duration average;
  final Duration p50;
  final Duration p95;
}

/// Frame timing monitor for detecting jank
class FrameMonitor {
  FrameMonitor._();

  static final _instance = FrameMonitor._();
  static FrameMonitor get instance => _instance;

  static const _targetFrameTime = Duration(milliseconds: 16); // 60fps
  static const _slowFrameThreshold = Duration(milliseconds: 32); // 30fps

  final _frameTimes = Queue<Duration>();
  final _slowFrames = <_FrameInfo>[];
  bool _isMonitoring = false;
  int _frameCount = 0;

  /// Start monitoring frames
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  /// Stop monitoring frames
  void stopMonitoring() {
    if (!_isMonitoring) return;
    _isMonitoring = false;

    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildDuration = Duration(
        microseconds: timing.buildDuration.inMicroseconds,
      );
      final rasterDuration = Duration(
        microseconds: timing.rasterDuration.inMicroseconds,
      );
      final totalDuration = buildDuration + rasterDuration;

      _frameTimes.add(totalDuration);
      if (_frameTimes.length > 120) {
        _frameTimes.removeFirst();
      }

      _frameCount++;

      if (totalDuration > _slowFrameThreshold) {
        _slowFrames.add(_FrameInfo(
          frameNumber: _frameCount,
          buildTime: buildDuration,
          rasterTime: rasterDuration,
          totalTime: totalDuration,
          timestamp: DateTime.now(),
        ));

        // Keep only last 50 slow frames
        if (_slowFrames.length > 50) {
          _slowFrames.removeAt(0);
        }

        if (kDebugMode) {
          print('⚠️ Slow frame #$_frameCount: ${totalDuration.inMilliseconds}ms '
              '(build: ${buildDuration.inMilliseconds}ms, '
              'raster: ${rasterDuration.inMilliseconds}ms)');
        }
      }
    }
  }

  /// Get average frame time
  Duration get averageFrameTime {
    if (_frameTimes.isEmpty) return Duration.zero;
    final total = _frameTimes.fold<int>(
      0,
      (sum, d) => sum + d.inMicroseconds,
    );
    return Duration(microseconds: total ~/ _frameTimes.length);
  }

  /// Get current FPS estimate
  double get estimatedFps {
    final avg = averageFrameTime;
    if (avg == Duration.zero) return 0;
    return 1000000 / avg.inMicroseconds;
  }

  /// Get slow frame count
  int get slowFrameCount => _slowFrames.length;

  /// Get slow frame percentage
  double get slowFramePercentage {
    if (_frameCount == 0) return 0;
    return (_slowFrames.length / _frameCount) * 100;
  }

  /// Get recent slow frames
  List<_FrameInfo> get recentSlowFrames => List.unmodifiable(_slowFrames);

  /// Print frame statistics
  void printStats() {
    if (!kDebugMode) return;

    print('═══════════════════════════════════════════════════════');
    print('                    FRAME STATISTICS                    ');
    print('═══════════════════════════════════════════════════════');
    print('📊 Total frames: $_frameCount');
    print('📊 Average frame time: ${averageFrameTime.inMicroseconds / 1000}ms');
    print('📊 Estimated FPS: ${estimatedFps.toStringAsFixed(1)}');
    print('⚠️ Slow frames: $slowFrameCount (${slowFramePercentage.toStringAsFixed(1)}%)');
  }

  /// Reset statistics
  void reset() {
    _frameTimes.clear();
    _slowFrames.clear();
    _frameCount = 0;
  }
}

class _FrameInfo {
  const _FrameInfo({
    required this.frameNumber,
    required this.buildTime,
    required this.rasterTime,
    required this.totalTime,
    required this.timestamp,
  });

  final int frameNumber;
  final Duration buildTime;
  final Duration rasterTime;
  final Duration totalTime;
  final DateTime timestamp;
}

/// Memory monitor for detecting leaks
class MemoryMonitor {
  MemoryMonitor._();

  static final _instance = MemoryMonitor._();
  static MemoryMonitor get instance => _instance;

  final _snapshots = <_MemorySnapshot>[];
  Timer? _monitorTimer;
  bool _isMonitoring = false;

  /// Start monitoring memory
  void startMonitoring({Duration interval = const Duration(seconds: 5)}) {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _monitorTimer = Timer.periodic(interval, (_) => _takeSnapshot());
  }

  /// Stop monitoring memory
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _isMonitoring = false;
  }

  void _takeSnapshot() {
    // Note: Actual memory info requires platform channels
    // This is a placeholder for the structure
    _snapshots.add(_MemorySnapshot(
      timestamp: DateTime.now(),
      heapUsage: 0, // Would need platform channel
      externalUsage: 0,
    ));

    // Keep only last 100 snapshots
    if (_snapshots.length > 100) {
      _snapshots.removeAt(0);
    }
  }

  /// Get memory trend (positive = growing, negative = shrinking)
  double? getMemoryTrend() {
    if (_snapshots.length < 2) return null;

    final recent = _snapshots.sublist(_snapshots.length - 10);
    if (recent.length < 2) return null;

    final first = recent.first.totalUsage;
    final last = recent.last.totalUsage;

    return (last - first) / first * 100;
  }

  /// Print memory statistics
  void printStats() {
    if (!kDebugMode || _snapshots.isEmpty) return;

    print('═══════════════════════════════════════════════════════');
    print('                   MEMORY STATISTICS                    ');
    print('═══════════════════════════════════════════════════════');
    print('📊 Snapshots: ${_snapshots.length}');
    if (_snapshots.isNotEmpty) {
      final latest = _snapshots.last;
      print('📊 Latest heap: ${(latest.heapUsage / 1024 / 1024).toStringAsFixed(2)}MB');
      print('📊 Latest external: ${(latest.externalUsage / 1024 / 1024).toStringAsFixed(2)}MB');
    }
    final trend = getMemoryTrend();
    if (trend != null) {
      print('📊 Trend: ${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%');
    }
  }

  /// Reset statistics
  void reset() {
    _snapshots.clear();
  }
}

class _MemorySnapshot {
  const _MemorySnapshot({
    required this.timestamp,
    required this.heapUsage,
    required this.externalUsage,
  });

  final DateTime timestamp;
  final int heapUsage;
  final int externalUsage;

  int get totalUsage => heapUsage + externalUsage;
}

/// Debounce helper for performance
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 300)});

  final Duration duration;
  Timer? _timer;

  void call(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// Throttle helper for performance
class Throttler {
  Throttler({this.duration = const Duration(milliseconds: 300)});

  final Duration duration;
  DateTime? _lastExecution;

  void call(VoidCallback action) {
    final now = DateTime.now();
    if (_lastExecution == null ||
        now.difference(_lastExecution!) >= duration) {
      _lastExecution = now;
      action();
    }
  }
}
