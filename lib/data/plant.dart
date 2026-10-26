/// What the unit does not know about the PV system: how the modules lie on the roof.
/// Needed for the forecast; entered once in the "Anlage" step.
library;

class PvString {
  final int modules, wp;
  const PvString({required this.modules, required this.wp});
  double get kwp => modules * wp / 1000;
  Map<String, int> toJson() => {'modules': modules, 'wp': wp};
  static PvString fromJson(Map<String, dynamic> j) => PvString(modules: j['modules'] as int, wp: j['wp'] as int);
}

/// One DC input of an inverter ("tracker") with its roof face.
class TrackerConfig {
  /// Inverter and input index as the unit reports them; identifies the tracker across sessions.
  final int pvi, index;
  final String name;

  /// Compass direction the modules face, 0 = north, 90 = east, 180 = south, 270 = west.
  final int azimuth;
  final int tilt;
  final List<PvString> strings;

  const TrackerConfig({
    required this.pvi,
    required this.index,
    required this.name,
    required this.azimuth,
    required this.tilt,
    required this.strings,
  });

  double get kwp => strings.fold(0, (a, s) => a + s.kwp);

  /// Azimuth as Open-Meteo expects it: 0 = south, −90 = east, 90 = west.
  int get azimuthSouth {
    var a = azimuth - 180;
    if (a > 180) a -= 360;
    if (a <= -180) a += 360;
    return a;
  }

  /// Short compass label, e.g. "SO".
  String get direction => const ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'][((azimuth % 360) / 45).round() % 8];

  TrackerConfig copyWith({String? name, int? azimuth, int? tilt, List<PvString>? strings}) => TrackerConfig(
    pvi: pvi,
    index: index,
    name: name ?? this.name,
    azimuth: azimuth ?? this.azimuth,
    tilt: tilt ?? this.tilt,
    strings: strings ?? this.strings,
  );

  Map<String, Object> toJson() => {
    'pvi': pvi,
    'index': index,
    'name': name,
    'azimuth': azimuth,
    'tilt': tilt,
    'strings': [for (final s in strings) s.toJson()],
  };

  static TrackerConfig fromJson(Map<String, dynamic> j) => TrackerConfig(
    pvi: j['pvi'] as int,
    index: j['index'] as int,
    name: j['name'] as String,
    azimuth: j['azimuth'] as int,
    tilt: j['tilt'] as int,
    strings: [for (final s in j['strings'] as List) PvString.fromJson(s as Map<String, dynamic>)],
  );
}

class PlantConfig {
  final double? latitude, longitude;

  /// Where the location came from, for display ("12345 Beispielstadt", "GPS", "manuell").
  final String? place;
  final List<TrackerConfig> trackers;

  const PlantConfig({this.latitude, this.longitude, this.place, this.trackers = const []});

  bool get hasLocation => latitude != null && longitude != null;

  /// Ready for a forecast: a location and at least one tracker with modules.
  bool get complete => hasLocation && trackers.isNotEmpty && trackers.every((t) => t.kwp > 0);

  double get kwp => trackers.fold(0, (a, t) => a + t.kwp);

  TrackerConfig? tracker(int pvi, int index) {
    for (final t in trackers) {
      if (t.pvi == pvi && t.index == index) return t;
    }
    return null;
  }

  PlantConfig copyWith({double? latitude, double? longitude, String? place, List<TrackerConfig>? trackers}) =>
      PlantConfig(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        place: place ?? this.place,
        trackers: trackers ?? this.trackers,
      );

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'place': place,
    'trackers': [for (final t in trackers) t.toJson()],
  };

  static PlantConfig fromJson(Map<String, dynamic> j) => PlantConfig(
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    place: j['place'] as String?,
    trackers: [for (final t in (j['trackers'] as List? ?? const [])) TrackerConfig.fromJson(t as Map<String, dynamic>)],
  );
}
