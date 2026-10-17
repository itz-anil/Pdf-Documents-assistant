import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';
import 'image_processing.dart';
import 'models.dart';

enum ImageQuality { high, balanced, small }

extension ImageQualityInfo on ImageQuality {
  String get label => switch (this) {
        ImageQuality.high => 'High',
        ImageQuality.balanced => 'Balanced',
        ImageQuality.small => 'Small',
      };
  String get hint => switch (this) {
        ImageQuality.high => 'Sharpest pages, larger files',
        ImageQuality.balanced => 'Best for everyday sharing',
        ImageQuality.small => 'Smallest files for email & chat',
      };
  int get maxSide => switch (this) {
        ImageQuality.high => 3200,
        ImageQuality.balanced => 2400,
        ImageQuality.small => 1600,
      };
  int get jpegQuality => switch (this) {
        ImageQuality.high => 90,
        ImageQuality.balanced => 82,
        ImageQuality.small => 68,
      };
}

enum PageSizeOption { fit, a4, letter }

extension PageSizeOptionInfo on PageSizeOption {
  String get label => switch (this) {
        PageSizeOption.fit => 'Fit to page image',
        PageSizeOption.a4 => 'A4',
        PageSizeOption.letter => 'US Letter',
      };
}

extension IdCardSizeInfo on IdCardSize {
  String get label => switch (this) {
        IdCardSize.large => 'Large',
        IdCardSize.actual => 'Actual size',
      };
  String get hint => switch (this) {
        IdCardSize.large => 'Both sides fill the page — easy to read',
        IdCardSize.actual => '85.6 × 54 mm, prints like a photocopy',
      };
}

class SettingsStore extends ChangeNotifier {
  late SharedPreferences _p;

  ThemeMode themeMode = ThemeMode.system;
  int accentIndex = 0;
  PageFilter defaultFilter = PageFilter.autoColor;
  bool autoOcr = true;
  IdCardSize idCardSize = IdCardSize.large;
  bool autoCapture = true;
  bool cameraGrid = false;
  ImageQuality quality = ImageQuality.balanced;
  PageSizeOption pageSize = PageSizeOption.fit;
  bool smartNames = true;
  String namePrefix = 'Scan';
  bool appLock = false;
  bool gridView = false;
  SortOrder sort = SortOrder.newest;
  bool haptics = true;
  String? savedSignature; // file name inside library dir

  AccentPalette get accent => accentPalettes[accentIndex.clamp(0, accentPalettes.length - 1)];

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[_p.getInt('theme') ?? ThemeMode.system.index];
    accentIndex = _p.getInt('accent') ?? 0;
    defaultFilter = PageFilter.values[_p.getInt('filter') ?? PageFilter.autoColor.index];
    autoOcr = _p.getBool('autoOcr') ?? true;
    idCardSize = IdCardSize.values[_p.getInt('idSize') ?? 0];
    autoCapture = _p.getBool('autoCapture') ?? true;
    cameraGrid = _p.getBool('cameraGrid') ?? false;
    quality = ImageQuality.values[_p.getInt('quality') ?? ImageQuality.balanced.index];
    pageSize = PageSizeOption.values[_p.getInt('pageSize') ?? PageSizeOption.fit.index];
    smartNames = _p.getBool('smartNames') ?? true;
    namePrefix = _p.getString('namePrefix') ?? 'Scan';
    appLock = _p.getBool('appLock') ?? false;
    gridView = _p.getBool('grid') ?? false;
    sort = SortOrder.values[_p.getInt('sort') ?? 0];
    haptics = _p.getBool('haptics') ?? true;
    savedSignature = _p.getString('signature');
  }

  void _commit(void Function() change, Future<bool> Function() persist) {
    change();
    notifyListeners();
    persist();
  }

  set setThemeMode(ThemeMode v) => _commit(() => themeMode = v, () => _p.setInt('theme', v.index));
  set setAccent(int v) => _commit(() => accentIndex = v, () => _p.setInt('accent', v));
  set setDefaultFilter(PageFilter v) => _commit(() => defaultFilter = v, () => _p.setInt('filter', v.index));
  set setAutoOcr(bool v) => _commit(() => autoOcr = v, () => _p.setBool('autoOcr', v));
  set setIdCardSize(IdCardSize v) => _commit(() => idCardSize = v, () => _p.setInt('idSize', v.index));
  set setAutoCapture(bool v) => _commit(() => autoCapture = v, () => _p.setBool('autoCapture', v));
  set setCameraGrid(bool v) => _commit(() => cameraGrid = v, () => _p.setBool('cameraGrid', v));
  set setQuality(ImageQuality v) => _commit(() => quality = v, () => _p.setInt('quality', v.index));
  set setPageSize(PageSizeOption v) => _commit(() => pageSize = v, () => _p.setInt('pageSize', v.index));
  set setSmartNames(bool v) => _commit(() => smartNames = v, () => _p.setBool('smartNames', v));
  set setNamePrefix(String v) => _commit(() => namePrefix = v, () => _p.setString('namePrefix', v));
  set setAppLock(bool v) => _commit(() => appLock = v, () => _p.setBool('appLock', v));
  set setGridView(bool v) => _commit(() => gridView = v, () => _p.setBool('grid', v));
  set setSort(SortOrder v) => _commit(() => sort = v, () => _p.setInt('sort', v.index));
  set setHaptics(bool v) => _commit(() => haptics = v, () => _p.setBool('haptics', v));
  set setSavedSignature(String? v) => _commit(
        () => savedSignature = v,
        () => v == null ? _p.remove('signature') : _p.setString('signature', v),
      );
}
