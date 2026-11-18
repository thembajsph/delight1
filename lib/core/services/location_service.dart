// lib/core/services/location_service.dart
// GPS location service for nearest agent finder
// Gracefully handles web (no GPS) and denied permissions

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static bool get isSupported => !kIsWeb;

  /// Request permission and get current position
  /// Returns null if permission denied or web
  static Future<Position?> getCurrentPosition() async {
    if (!isSupported) return null;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }

  /// Calculate distance in km between two coordinates
  static double distanceKm(
      double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  /// Stream position updates (for live tracking)
  static Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50)); // update every 50m
  }
}

/// An agent location with distance from user
class AgentLocation {
  final String name;
  final String address;
  final double lat, lng;
  final String rating;
  final bool isOpen;
  final double distanceKm;
  final List<String> services; // ['cashout', 'topup', 'airtime']

  const AgentLocation({
    required this.name, required this.address,
    required this.lat,  required this.lng,
    required this.rating, required this.isOpen,
    required this.distanceKm, required this.services,
  });
}

/// Find nearest agents sorted by distance
Future<List<AgentLocation>> findNearestAgents() async {
  final pos = await LocationService.getCurrentPosition();

  // Seed agents with real SA coordinates for testing
  // In production: query Supabase agents table filtered by ST_DWithin
  final seedAgents = [
    _seed('Mama Tuck Shop',     'Soweto, GP',       -26.2485, 27.8538, '4.9', true,  ['cashout','topup']),
    _seed('Flash Spaza',        'Alexandra, GP',    -26.0969, 28.0997, '4.7', true,  ['cashout','topup','airtime']),
    _seed('Kazang Point',       'Khayelitsha, WC',  -34.0357, 18.6922, '4.6', true,  ['cashout','topup']),
    _seed('Corner Shop Agent',  'Mitchells Plain',  -34.0485, 18.6241, '4.5', false, ['topup']),
    _seed('Delight Agent Hub',  'Sandton, GP',      -26.1077, 28.0567, '5.0', true,  ['cashout','topup','airtime']),
  ];

  if (pos == null) return seedAgents; // no GPS — return all unsorted

  // Sort by distance from user
  final withDistance = seedAgents.map((a) {
    final d = LocationService.distanceKm(pos.latitude, pos.longitude, a.lat, a.lng);
    return AgentLocation(
      name: a.name, address: a.address, lat: a.lat, lng: a.lng,
      rating: a.rating, isOpen: a.isOpen, distanceKm: d, services: a.services);
  }).toList()
    ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

  return withDistance;
}

AgentLocation _seed(String name, String address,
    double lat, double lng, String rating, bool open, List<String> services) =>
  AgentLocation(name: name, address: address, lat: lat, lng: lng,
    rating: rating, isOpen: open, distanceKm: 0, services: services);
