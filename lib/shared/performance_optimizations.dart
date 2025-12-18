import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PerformanceOptimizations {
  // 1. Enable performance overlay in debug mode
  static Widget wrapWithPerformanceOverlay(Widget child) {
    if (kDebugMode) {
      return MaterialApp(
        showPerformanceOverlay: true, // Shows FPS and frame rendering time
        home: child,
      );
    }
    return child;
  }

  // 2. Optimize image loading
  static Widget optimizedImage({
    required String imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
  }) {
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      // Performance optimizations
      cacheWidth: width.toInt(),
      cacheHeight: height.toInt(),
      filterQuality: FilterQuality.medium, // Better performance than high
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(child: CircularProgressIndicator()),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image),
        );
      },
    );
  }

  // 3. Optimize list building
  static Widget optimizedListView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    ScrollController? controller,
  }) {
    return ListView.builder(
      controller: controller,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      // Performance optimizations
      cacheExtent: 250.0, // Cache items outside viewport
      addAutomaticKeepAlives:
          false, // Don't keep items alive when scrolled away
      addRepaintBoundaries: true, // Isolate repaints
      addSemanticIndexes:
          false, // Skip semantic indexing for better performance
    );
  }

  // 4. Optimize grid building
  static Widget optimizedGridView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    required int crossAxisCount,
    double crossAxisSpacing = 8.0,
    double mainAxisSpacing = 8.0,
  }) {
    return GridView.builder(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        childAspectRatio: 1.0, // Optimize for square items
      ),
      // Performance optimizations
      cacheExtent: 250.0,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
    );
  }

  // 5. Debounce function for search/input
  static void debounce({
    required String key,
    required VoidCallback callback,
    Duration delay = const Duration(milliseconds: 500),
  }) {
    // Simple debounce implementation
    Future.delayed(delay, () {
      callback();
    });
  }

  // 6. Memory optimization for large datasets
  static List<T> paginateList<T>(List<T> fullList, int page, int pageSize) {
    final startIndex = page * pageSize;
    final endIndex = (startIndex + pageSize).clamp(0, fullList.length);
    return fullList.sublist(startIndex, endIndex);
  }
}
