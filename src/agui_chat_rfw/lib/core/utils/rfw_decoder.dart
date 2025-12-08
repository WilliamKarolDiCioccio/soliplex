import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rfw/rfw.dart';
import 'package:rfw/formats.dart' as rfw_formats;

import 'security_validator.dart';
import 'lru_cache.dart';

/// Result of decoding an RFW library.
class DecodeResult {
  final RemoteWidgetLibrary? library;
  final String? error;
  final Duration decodeDuration;

  DecodeResult({
    this.library,
    this.error,
    required this.decodeDuration,
  });

  bool get isSuccess => library != null && error == null;
}

/// Isolate-based RFW decoder for non-blocking binary parsing.
///
/// Moves heavy decoding work off the main thread to maintain 60fps UI.
/// Implements caching to avoid redundant decoding of repeated payloads.
class RfwDecoder {
  RfwDecoder._();

  static final RfwDecoder _instance = RfwDecoder._();
  static RfwDecoder get instance => _instance;

  /// Cache for decoded libraries keyed by hash of binary blob.
  final LruCache<String, RemoteWidgetLibrary> _cache = LruCache(maxSize: 50);

  /// Decode a binary RFW blob in an isolate.
  ///
  /// Returns a [DecodeResult] containing either the decoded library or an error.
  /// Results are cached by content hash to avoid redundant decoding.
  Future<DecodeResult> decodeBinary(Uint8List blob) async {
    final stopwatch = Stopwatch()..start();

    // Validate payload size first (cheap check on main thread)
    if (!SecurityValidator.isValidPayloadSize(blob.length)) {
      stopwatch.stop();
      return DecodeResult(
        error: 'Payload exceeds maximum size (${blob.length} > ${SecurityValidator.maxPayloadSize})',
        decodeDuration: stopwatch.elapsed,
      );
    }

    // Check cache using content hash
    final cacheKey = _computeHash(blob);
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      stopwatch.stop();
      debugPrint('RfwDecoder: Cache hit for blob hash $cacheKey');
      return DecodeResult(
        library: cached,
        decodeDuration: stopwatch.elapsed,
      );
    }

    try {
      // Decode in isolate to avoid blocking main thread
      final library = await compute(_decodeInIsolate, blob);

      stopwatch.stop();

      if (library != null) {
        _cache.put(cacheKey, library);
        debugPrint('RfwDecoder: Decoded and cached blob in ${stopwatch.elapsedMilliseconds}ms');
        return DecodeResult(
          library: library,
          decodeDuration: stopwatch.elapsed,
        );
      } else {
        return DecodeResult(
          error: 'Failed to decode library blob',
          decodeDuration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint('RfwDecoder: Error decoding blob: $e');
      return DecodeResult(
        error: 'Decode error: $e',
        decodeDuration: stopwatch.elapsed,
      );
    }
  }

  /// Parse RFW text format in an isolate.
  ///
  /// Useful for development. In production, prefer binary format.
  Future<DecodeResult> parseText(String source) async {
    final stopwatch = Stopwatch()..start();

    // Validate payload size
    final sizeInBytes = source.length * 2; // UTF-16 approximation
    if (!SecurityValidator.isValidPayloadSize(sizeInBytes)) {
      stopwatch.stop();
      return DecodeResult(
        error: 'Text payload exceeds maximum size',
        decodeDuration: stopwatch.elapsed,
      );
    }

    // Check cache
    final cacheKey = _computeStringHash(source);
    final cached = _cache.get(cacheKey);
    if (cached != null) {
      stopwatch.stop();
      return DecodeResult(
        library: cached,
        decodeDuration: stopwatch.elapsed,
      );
    }

    try {
      final library = await compute(_parseTextInIsolate, source);

      stopwatch.stop();

      if (library != null) {
        _cache.put(cacheKey, library);
        return DecodeResult(
          library: library,
          decodeDuration: stopwatch.elapsed,
        );
      } else {
        return DecodeResult(
          error: 'Failed to parse text library',
          decodeDuration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return DecodeResult(
        error: 'Parse error: $e',
        decodeDuration: stopwatch.elapsed,
      );
    }
  }

  /// Decode multiple blobs in parallel using isolate pool.
  ///
  /// Returns results in the same order as input blobs.
  Future<List<DecodeResult>> decodeMany(List<Uint8List> blobs) async {
    final futures = blobs.map((blob) => decodeBinary(blob));
    return Future.wait(futures);
  }

  /// Clear the decode cache.
  void clearCache() {
    _cache.clear();
    debugPrint('RfwDecoder: Cache cleared');
  }

  /// Get cache statistics.
  CacheStats get cacheStats => CacheStats(
        hits: _cache.hits,
        misses: _cache.misses,
        size: _cache.length,
        maxSize: _cache.maxSize,
      );

  /// Compute a simple hash for caching purposes.
  String _computeHash(Uint8List data) {
    // Simple FNV-1a hash for fast cache key generation
    int hash = 2166136261;
    for (final byte in data) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  String _computeStringHash(String data) {
    int hash = 2166136261;
    for (final char in data.codeUnits) {
      hash ^= char;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return 'txt_${hash.toRadixString(16)}';
  }
}

/// Top-level function for isolate execution (binary decode).
RemoteWidgetLibrary? _decodeInIsolate(Uint8List blob) {
  try {
    return decodeLibraryBlob(blob);
  } catch (e) {
    return null;
  }
}

/// Top-level function for isolate execution (text parse).
RemoteWidgetLibrary? _parseTextInIsolate(String source) {
  try {
    return rfw_formats.parseLibraryFile(source);
  } catch (e) {
    return null;
  }
}

/// Cache statistics container.
class CacheStats {
  final int hits;
  final int misses;
  final int size;
  final int maxSize;

  CacheStats({
    required this.hits,
    required this.misses,
    required this.size,
    required this.maxSize,
  });

  double get hitRate => (hits + misses) > 0 ? hits / (hits + misses) : 0.0;

  @override
  String toString() => 'CacheStats(hits: $hits, misses: $misses, size: $size/$maxSize, hitRate: ${(hitRate * 100).toStringAsFixed(1)}%)';
}
