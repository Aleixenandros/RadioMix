import '../../models/radio_station.dart';

abstract class RadioSearchProvider {
  String get id;
  String get displayName;
  bool get requiresApiKey;

  Future<List<RadioStation>> searchStations(String query);
  Future<List<RadioStation>> getPopularStations();
}
