import 'package:flutter/material.dart';

class PhotoCategory {
  const PhotoCategory({
    required this.value,
    required this.label,
    required this.color,
    required this.softColor,
    required this.icon,
  });

  final String value;
  final String label;
  final Color color;
  final Color softColor;
  final IconData icon;
}

const List<PhotoCategory> kPhotoCategories = <PhotoCategory>[
  PhotoCategory(
    value: 'asap',
    label: 'ASAP',
    color: Color(0xFFEF4444),
    softColor: Color(0xFFFEE2E2),
    icon: Icons.bolt_rounded,
  ),
  PhotoCategory(
    value: 'special',
    label: 'Special',
    color: Color(0xFFF97316),
    softColor: Color(0xFFFFEDD5),
    icon: Icons.star_rounded,
  ),
  PhotoCategory(
    value: 'standard',
    label: 'Standard',
    color: Color(0xFF10B981),
    softColor: Color(0xFFD1FAE5),
    icon: Icons.check_circle_rounded,
  ),
  PhotoCategory(
    value: 'next_day',
    label: 'Next Day',
    color: Color(0xFFEAB308),
    softColor: Color(0xFFFEF9C3),
    icon: Icons.event_rounded,
  ),
];

const String kDefaultCategory = 'standard';

PhotoCategory categoryOf(String? value) {
  final v = (value ?? kDefaultCategory).toLowerCase();
  return kPhotoCategories.firstWhere(
    (c) => c.value == v,
    orElse: () => kPhotoCategories.first,
  );
}

String categoryLabel(String? value) => categoryOf(value).label;
Color categoryColor(String? value) => categoryOf(value).color;
Color categorySoftColor(String? value) => categoryOf(value).softColor;
