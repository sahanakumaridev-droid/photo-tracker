import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Gray street map: roads, water, parks, and labels stay visible.
/// Color is removed so OSM-style red/orange highways do not appear.
class AppMapTiles {
  AppMapTiles._();

  static const urlTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';

  static const userAgentPackageName = 'com.example.photo_tracker';

  static const ColorFilter _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  static Widget _grayscaleTile(BuildContext _, Widget tile, TileImage __) {
    return ColorFiltered(colorFilter: _grayscale, child: tile);
  }

  static TileLayer layer() => TileLayer(
        key: const ValueKey('esri-street-gray-v2'),
        urlTemplate: urlTemplate,
        userAgentPackageName: userAgentPackageName,
        tileSize: 256,
        retinaMode: false,
        tileBuilder: _grayscaleTile,
      );
}
