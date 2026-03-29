import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class ImageProcessingUtil {
  /// Cache for already calculated hashes to avoid reprocessing
  static final Map<String, List<bool>> _hashCache = {};

  /// Threshold for determining duplicate images (0-100)
  final double similarityThreshold;

  /// Size of the perceptual hash (smaller = faster, less accurate)
  final int hashSize;

  /// Constructor with default parameters
  ImageProcessingUtil({
    this.similarityThreshold = 80.0, // 80% similarity
    this.hashSize = 8, // 8x8 grid is fast and reasonably accurate
  });

  /// Check if a file is an image based on extension
  static bool isImageFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext);
  }

  /// Calculate perceptual hash for an image efficiently
  Future<List<bool>?> calculatePerceptualHash(String imagePath) async {
    // Check cache first
    if (_hashCache.containsKey(imagePath)) {
      return _hashCache[imagePath];
    }

    try {
      final file = File(imagePath);

      // Check if file exists
      if (!await file.exists()) {
        return null;
      }

      // Load image bytes
      final bytes = await file.readAsBytes();

      // Use compute for heavy processing to avoid blocking the UI thread
      final hash = await compute(_calculateHashInIsolate, bytes);

      // Cache the result
      if (hash != null) {
        _hashCache[imagePath] = hash;
      }

      return hash;
    } catch (e) {
      print('Error calculating hash for $imagePath: $e');
      return null;
    }
  }

  /// Process and hash an image in a separate isolate
  static List<bool>? _calculateHashInIsolate(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);

      if (image == null) return null;

      // Use a small size for faster processing
      const hashSize = 8;

      // Resize to small square for hash calculation (use nearest neighbor for speed)
      final resized = img.copyResize(
        image,
        width: hashSize,
        height: hashSize,
        interpolation: img.Interpolation.nearest,
      );

      // Convert to grayscale
      final grayscale = img.grayscale(resized);
      final pixels = grayscale.data;

      if (pixels == null || pixels.isEmpty) return null;

      // Calculate average luminance
      int sum = 0;
      for (var pixel in pixels) {
        // Quick grayscale approximation
        int grayscaleValue = ((pixel.r + pixel.g + pixel.b) ~/ 3);
        sum += grayscaleValue;
      }

      final avg = (sum / pixels.length).round();

      // Generate hash based on whether pixel is above or below average
      return pixels.map((pixel) {
        int grayscaleValue = ((pixel.r + pixel.g + pixel.b) ~/ 3);
        return grayscaleValue > avg;
      }).toList();
    } catch (e) {
      print('Error in hash calculation: $e');
      return null;
    }
  }
  /// Compare two image hashes with optimized algorithm
  double compareHashes(List<bool> hash1, List<bool> hash2) {
    if (hash1.length != hash2.length) return 0.0;

    int differences = 0;
    final maxDifferences = (hash1.length * (1 - similarityThreshold / 100)).ceil();

    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) {
        differences++;

        // Early termination if we exceed the maximum allowed differences
        if (differences > maxDifferences) {
          return 0.0;
        }
      }
    }

    return ((hash1.length - differences) / hash1.length) * 100;
  }

  /// Generate a unique hash for a group of images
  String generateGroupHash(List<String> paths) {
    // Sort paths for consistent hash generation
    final sortedPaths = List<String>.from(paths)..sort();
    final combinedPaths = sortedPaths.join(':');
    return md5.convert(utf8.encode(combinedPaths)).toString();
  }

  /// Clear the hash cache to free memory
  void clearCache() {
    _hashCache.clear();
  }

  /// Process images in parallel to find duplicates
  Future<List<List<String>>> findDuplicateGroups(List<String> imagePaths) async {
    // Group by similar file sizes first (within 1KB)
    final sizeGroups = await _groupBySimilarSize(imagePaths);

    final List<List<String>> duplicateGroups = [];

    // Process each size group in parallel
    await Future.wait(sizeGroups.map((group) async {
      if (group.length < 2) return; // Skip groups with only one image

      // Calculate hashes for all images in this group
      final Map<String, List<bool>> hashes = {};

      await Future.wait(group.map((path) async {
        final hash = await calculatePerceptualHash(path);
        if (hash != null) {
          hashes[path] = hash;
        }
      }));

      // Build similarity graph
      final Map<String, Set<String>> similarityGraph = {};

      for (var path in hashes.keys) {
        similarityGraph[path] = {};
      }

      // Compare each pair of images
      for (var i = 0; i < group.length; i++) {
        final pathA = group[i];
        final hashA = hashes[pathA];

        if (hashA == null) continue;

        for (var j = i + 1; j < group.length; j++) {
          final pathB = group[j];
          final hashB = hashes[pathB];

          if (hashB == null) continue;

          final similarity = compareHashes(hashA, hashB);

          if (similarity >= similarityThreshold) {
            similarityGraph[pathA]?.add(pathB);
            similarityGraph[pathB]?.add(pathA);
          }
        }
      }

      // Find connected components (duplicate groups)
      final components = _findConnectedComponents(similarityGraph);
      duplicateGroups.addAll(components);
    }));

    return duplicateGroups;
  }

  /// Group images by similar file size
  Future<List<List<String>>> _groupBySimilarSize(List<String> imagePaths) async {
    final Map<int, List<String>> sizeGroups = {};

    for (var path in imagePaths) {
      try {
        final file = File(path);
        final size = await file.length();

        // Round size to nearest KB for grouping similar-sized files
        final sizeKey = (size / 1024).round();

        if (!sizeGroups.containsKey(sizeKey)) {
          sizeGroups[sizeKey] = [];
        }

        sizeGroups[sizeKey]!.add(path);
      } catch (e) {
        print('Error getting file size for $path: $e');
      }
    }

    // Only return groups with potential duplicates
    return sizeGroups.values.where((group) => group.length >= 2).toList();
  }

  /// Find connected components in a graph using DFS
  List<List<String>> _findConnectedComponents(Map<String, Set<String>> graph) {
    final List<List<String>> components = [];
    final Set<String> visited = {};

    for (var node in graph.keys) {
      if (!visited.contains(node)) {
        final component = <String>[];
        _dfs(node, graph, visited, component);

        if (component.length >= 2) {
          components.add(component);
        }
      }
    }

    return components;
  }

  /// Depth-first search helper function
  void _dfs(String node, Map<String, Set<String>> graph, Set<String> visited, List<String> component) {
    visited.add(node);
    component.add(node);

    for (var neighbor in graph[node] ?? {}) {
      if (!visited.contains(neighbor)) {
        _dfs(neighbor, graph, visited, component);
      }
    }
  }
}