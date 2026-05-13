import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connectivity status
enum ConnectivityStatus { online, offline, unknown }

/// Connectivity monitor interface
abstract class ConnectivityMonitor {
  Stream<ConnectivityStatus> get statusStream;
  ConnectivityStatus get currentStatus;
  Future<bool> checkConnectivity();
}

/// Simple connectivity monitor using periodic checks
class SimpleConnectivityMonitor implements ConnectivityMonitor {
  SimpleConnectivityMonitor({
    this.checkInterval = const Duration(seconds: 30),
    this.checkUrl = 'https://www.google.com',
  });

  final Duration checkInterval;
  final String checkUrl;

  final _statusController = StreamController<ConnectivityStatus>.broadcast();
  Timer? _checkTimer;
  ConnectivityStatus _currentStatus = ConnectivityStatus.unknown;

  @override
  Stream<ConnectivityStatus> get statusStream => _statusController.stream;

  @override
  ConnectivityStatus get currentStatus => _currentStatus;

  /// Start monitoring connectivity
  void startMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(checkInterval, (_) => checkConnectivity());
    checkConnectivity(); // Initial check
  }

  /// Stop monitoring
  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  @override
  Future<bool> checkConnectivity() async {
    try {
      // In a real app, you'd use connectivity_plus package
      // For now, we'll assume online
      _updateStatus(ConnectivityStatus.online);
      return true;
    } catch (e) {
      _updateStatus(ConnectivityStatus.offline);
      return false;
    }
  }

  void _updateStatus(ConnectivityStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);

      if (kDebugMode) {
        print('📡 Connectivity: $status');
      }
    }
  }

  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}

/// Offline queue item
class QueuedOperation {
  QueuedOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.priority = 0,
    this.maxRetries = 3,
    this.retryCount = 0,
  });

  final String id;
  final String type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int priority;
  final int maxRetries;
  int retryCount;

  bool get canRetry => retryCount < maxRetries;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'priority': priority,
        'maxRetries': maxRetries,
        'retryCount': retryCount,
      };

  factory QueuedOperation.fromJson(Map<String, dynamic> json) => QueuedOperation(
        id: json['id'] as String,
        type: json['type'] as String,
        data: json['data'] as Map<String, dynamic>,
        createdAt: DateTime.parse(json['createdAt'] as String),
        priority: json['priority'] as int? ?? 0,
        maxRetries: json['maxRetries'] as int? ?? 3,
        retryCount: json['retryCount'] as int? ?? 0,
      );
}

/// Offline operation queue for syncing when online
class OfflineQueue {
  OfflineQueue({this.storageKey = 'offline_queue'});

  final String storageKey;
  final _queue = <QueuedOperation>[];
  final _handlers = <String, Future<bool> Function(Map<String, dynamic>)>{};
  final _processingController = StreamController<QueuedOperation>.broadcast();

  SharedPreferences? _prefs;
  bool _isProcessing = false;

  /// Stream of operations being processed
  Stream<QueuedOperation> get processingStream => _processingController.stream;

  /// Current queue size
  int get size => _queue.length;

  /// Check if queue is empty
  bool get isEmpty => _queue.isEmpty;

  /// Initialize the queue from storage
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFromStorage();
  }

  /// Register a handler for an operation type
  void registerHandler(
    String type,
    Future<bool> Function(Map<String, dynamic> data) handler,
  ) {
    _handlers[type] = handler;
  }

  /// Add an operation to the queue
  Future<void> enqueue(QueuedOperation operation) async {
    _queue.add(operation);
    _sortQueue();
    await _saveToStorage();

    if (kDebugMode) {
      print('📥 Queued operation: ${operation.type} (${operation.id})');
    }
  }

  /// Create and add an operation
  Future<void> add({
    required String type,
    required Map<String, dynamic> data,
    int priority = 0,
  }) async {
    final operation = QueuedOperation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      data: data,
      createdAt: DateTime.now(),
      priority: priority,
    );
    await enqueue(operation);
  }

  /// Process all queued operations
  Future<void> processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    if (kDebugMode) {
      print('🔄 Processing offline queue (${_queue.length} items)...');
    }

    final toRemove = <QueuedOperation>[];
    final failed = <QueuedOperation>[];

    for (final operation in List.from(_queue)) {
      final handler = _handlers[operation.type];
      if (handler == null) {
        if (kDebugMode) {
          print('⚠️ No handler for operation type: ${operation.type}');
        }
        continue;
      }

      _processingController.add(operation);

      try {
        final success = await handler(operation.data);
        if (success) {
          toRemove.add(operation);
          if (kDebugMode) {
            print('✅ Processed: ${operation.type} (${operation.id})');
          }
        } else {
          operation.retryCount++;
          if (!operation.canRetry) {
            failed.add(operation);
          }
        }
      } catch (e) {
        operation.retryCount++;
        if (!operation.canRetry) {
          failed.add(operation);
        }
        if (kDebugMode) {
          print('❌ Failed: ${operation.type} (${operation.id}) - $e');
        }
      }
    }

    // Remove successful and exhausted operations
    _queue.removeWhere((op) => toRemove.contains(op) || failed.contains(op));
    await _saveToStorage();

    _isProcessing = false;

    if (kDebugMode) {
      print('📤 Queue processing complete. Remaining: ${_queue.length}');
    }
  }

  /// Clear the queue
  Future<void> clear() async {
    _queue.clear();
    await _saveToStorage();
  }

  /// Get all pending operations
  List<QueuedOperation> get pendingOperations => List.unmodifiable(_queue);

  void _sortQueue() {
    _queue.sort((a, b) {
      // Higher priority first, then older first
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  Future<void> _loadFromStorage() async {
    final json = _prefs?.getString(storageKey);
    if (json == null) return;

    try {
      final list = jsonDecode(json) as List;
      _queue.clear();
      _queue.addAll(
        list.map((e) => QueuedOperation.fromJson(e as Map<String, dynamic>)),
      );
      _sortQueue();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to load offline queue: $e');
      }
    }
  }

  Future<void> _saveToStorage() async {
    final json = jsonEncode(_queue.map((e) => e.toJson()).toList());
    await _prefs?.setString(storageKey, json);
  }

  void dispose() {
    _processingController.close();
  }
}

/// Cache entry with metadata
class CacheEntry<T> {
  CacheEntry({
    required this.key,
    required this.value,
    required this.createdAt,
    this.expiresAt,
    this.tags = const [],
  });

  final String key;
  final T value;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final List<String> tags;

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Duration? get timeToLive =>
      expiresAt?.difference(DateTime.now());
}

/// In-memory cache with TTL and tags support
class MemoryCache<T> {
  MemoryCache({
    this.maxSize = 100,
    this.defaultTtl = const Duration(minutes: 5),
  });

  final int maxSize;
  final Duration defaultTtl;

  final _cache = LinkedHashMap<String, CacheEntry<T>>();

  /// Get a cached value
  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }

    // Move to end (LRU)
    _cache.remove(key);
    _cache[key] = entry;

    return entry.value;
  }

  /// Set a cached value
  void set(
    String key,
    T value, {
    Duration? ttl,
    List<String> tags = const [],
  }) {
    // Evict if at capacity
    while (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = CacheEntry(
      key: key,
      value: value,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(ttl ?? defaultTtl),
      tags: tags,
    );
  }

  /// Get or set a cached value
  Future<T> getOrSet(
    String key,
    Future<T> Function() fetch, {
    Duration? ttl,
    List<String> tags = const [],
  }) async {
    final cached = get(key);
    if (cached != null) return cached;

    final value = await fetch();
    set(key, value, ttl: ttl, tags: tags);
    return value;
  }

  /// Remove a cached value
  void remove(String key) {
    _cache.remove(key);
  }

  /// Remove all values with a specific tag
  void removeByTag(String tag) {
    _cache.removeWhere((_, entry) => entry.tags.contains(tag));
  }

  /// Clear all cached values
  void clear() {
    _cache.clear();
  }

  /// Remove expired entries
  void cleanUp() {
    _cache.removeWhere((_, entry) => entry.isExpired);
  }

  /// Get cache statistics
  CacheStats get stats => CacheStats(
        size: _cache.length,
        maxSize: maxSize,
        oldestEntry: _cache.isEmpty ? null : _cache.values.first.createdAt,
        newestEntry: _cache.isEmpty ? null : _cache.values.last.createdAt,
      );
}

/// Cache statistics
class CacheStats {
  const CacheStats({
    required this.size,
    required this.maxSize,
    this.oldestEntry,
    this.newestEntry,
  });

  final int size;
  final int maxSize;
  final DateTime? oldestEntry;
  final DateTime? newestEntry;

  double get fillPercentage => size / maxSize * 100;
}

/// Offline-first data manager
class OfflineFirstManager<T> {
  OfflineFirstManager({
    required this.fetchFromNetwork,
    required this.saveToLocal,
    required this.loadFromLocal,
    this.cache,
    this.cacheTtl = const Duration(minutes: 5),
  });

  final Future<T> Function() fetchFromNetwork;
  final Future<void> Function(T data) saveToLocal;
  final Future<T?> Function() loadFromLocal;
  final MemoryCache<T>? cache;
  final Duration cacheTtl;

  /// Get data with offline-first strategy
  Future<T?> get({
    String? cacheKey,
    bool forceRefresh = false,
  }) async {
    // 1. Check memory cache
    if (!forceRefresh && cacheKey != null && cache != null) {
      final cached = cache!.get(cacheKey);
      if (cached != null) {
        if (kDebugMode) print('📦 Cache hit: $cacheKey');
        return cached;
      }
    }

    // 2. Try network
    try {
      final data = await fetchFromNetwork();
      await saveToLocal(data);

      if (cacheKey != null && cache != null) {
        cache!.set(cacheKey, data, ttl: cacheTtl);
      }

      if (kDebugMode) print('🌐 Network fetch successful');
      return data;
    } catch (e) {
      if (kDebugMode) print('⚠️ Network fetch failed: $e');
    }

    // 3. Fall back to local storage
    final local = await loadFromLocal();
    if (local != null) {
      if (cacheKey != null && cache != null) {
        cache!.set(cacheKey, local, ttl: cacheTtl);
      }
      if (kDebugMode) print('💾 Loaded from local storage');
    }

    return local;
  }
}

/// Sync status for data
enum SyncStatus { synced, pending, error, conflict }

/// Syncable item wrapper
class SyncableItem<T> {
  SyncableItem({
    required this.data,
    required this.lastModified,
    this.syncStatus = SyncStatus.pending,
    this.syncError,
  });

  final T data;
  final DateTime lastModified;
  SyncStatus syncStatus;
  String? syncError;

  bool get needsSync => syncStatus == SyncStatus.pending;
}

/// Sync manager for bidirectional sync
class SyncManager<T> {
  SyncManager({
    required this.upload,
    required this.download,
    required this.resolveConflict,
    this.onSyncComplete,
    this.onSyncError,
  });

  final Future<void> Function(T item) upload;
  final Future<List<T>> Function(DateTime? lastSync) download;
  final T Function(T local, T remote) resolveConflict;
  final void Function(int uploaded, int downloaded)? onSyncComplete;
  final void Function(Object error)? onSyncError;

  DateTime? _lastSync;
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSync => _lastSync;

  /// Perform full sync
  Future<void> sync(List<SyncableItem<T>> localItems) async {
    if (_isSyncing) return;
    _isSyncing = true;

    int uploaded = 0;
    int downloaded = 0;

    try {
      // Upload pending items
      for (final item in localItems.where((i) => i.needsSync)) {
        try {
          await upload(item.data);
          item.syncStatus = SyncStatus.synced;
          uploaded++;
        } catch (e) {
          item.syncStatus = SyncStatus.error;
          item.syncError = e.toString();
        }
      }

      // Download remote changes
      final remoteItems = await download(_lastSync);
      downloaded = remoteItems.length;

      _lastSync = DateTime.now();
      onSyncComplete?.call(uploaded, downloaded);

      if (kDebugMode) {
        print('🔄 Sync complete: ↑$uploaded ↓$downloaded');
      }
    } catch (e) {
      onSyncError?.call(e);
      if (kDebugMode) {
        print('❌ Sync failed: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }
}

/// Network-aware operation wrapper
Future<T> withOfflineSupport<T>({
  required Future<T> Function() onlineOperation,
  required Future<T> Function() offlineOperation,
  required ConnectivityMonitor connectivity,
}) async {
  if (connectivity.currentStatus == ConnectivityStatus.online) {
    try {
      return await onlineOperation();
    } catch (e) {
      // Fall back to offline on network errors
      if (_isNetworkError(e)) {
        return offlineOperation();
      }
      rethrow;
    }
  }
  return offlineOperation();
}

bool _isNetworkError(Object error) {
  final errorString = error.toString().toLowerCase();
  return errorString.contains('network') ||
      errorString.contains('socket') ||
      errorString.contains('connection') ||
      errorString.contains('timeout');
}
