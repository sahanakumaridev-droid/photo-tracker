import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LoadingSkeleton extends StatelessWidget {

  const LoadingSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius,
  });
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
    baseColor: const Color(0xFF1C222E),
    highlightColor: const Color(0xFF2A3340),
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1C222E),
        borderRadius: borderRadius ?? BorderRadius.circular(4),
      ),
    ),
  );
}

class LoadingSkeletonCard extends StatelessWidget {
  const LoadingSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFF2A3340),
        width: 1,
      ),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Shimmer.fromColors(
            baseColor: const Color(0xFF1C222E),
            highlightColor: const Color(0xFF2A3340),
            child: Container(
              height: 200,
              color: const Color(0xFF1C222E),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoadingSkeleton(
                  width: 120,
                  height: 14,
                ),
                SizedBox(height: 8),
                LoadingSkeleton(
                  width: 80,
                  height: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class PhotoCardSkeleton extends StatelessWidget {
  const PhotoCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFF1C222E),
            child: Shimmer.fromColors(
              baseColor: const Color(0xFF1C222E),
              highlightColor: const Color(0xFF2A3340),
              child: Container(
                color: const Color(0xFF1C222E),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoadingSkeleton(
                width: 100,
                height: 12,
              ),
              SizedBox(height: 8),
              LoadingSkeleton(
                width: 60,
                height: 20,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ProfileListSkeleton extends StatelessWidget {
  const ProfileListSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: Shimmer.fromColors(
        baseColor: const Color(0xFF1C222E),
        highlightColor: const Color(0xFF2A3340),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF1C222E),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      title: const LoadingSkeleton(
        width: 100,
        height: 16,
      ),
      subtitle: const LoadingSkeleton(
        width: 80,
        height: 12,
      ),
    ),
  );
}
