import 'package:flutter/cupertino.dart';

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
    icon: CupertinoIcons.bolt_fill,
  ),
  PhotoCategory(
    value: 'special',
    label: 'Special',
    color: Color(0xFFC2410C), // orange-700: dark enough to read on light bg
    softColor: Color(0xFFFFEDD5), // orange-100: light so text pops
    icon: CupertinoIcons.star_fill,
  ),
  PhotoCategory(
    value: 'standard',
    label: 'Standard',
    color: Color(0xFF10B981),
    softColor: Color(0xFFD1FAE5),
    icon: CupertinoIcons.checkmark_seal_fill,
  ),
  PhotoCategory(
    value: 'next_day',
    label: 'Next Day',
    color: Color(0xFFB45309), // amber-700: dark brown-gold, clear on yellow bg
    softColor: Color(0xFFFEF3C7), // amber-100: light yellow so text pops
    icon: CupertinoIcons.calendar,
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
