import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Represents a room from the AG-UI server.
class Room {
  final String id;
  final String name;
  final String? description;

  const Room({
    required this.id,
    required this.name,
    this.description,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] as String? ?? json['name'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      description: json['description'] as String?,
    );
  }

  @override
  String toString() => 'Room($id: $name)';
}

/// State for rooms list.
class RoomsState {
  final List<Room> rooms;
  final bool isLoading;
  final String? error;

  const RoomsState({
    this.rooms = const [],
    this.isLoading = false,
    this.error,
  });

  RoomsState copyWith({
    List<Room>? rooms,
    bool? isLoading,
    String? error,
  }) {
    return RoomsState(
      rooms: rooms ?? this.rooms,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Notifier for managing rooms state.
class RoomsNotifier extends StateNotifier<RoomsState> {
  final http.Client _httpClient;
  String _baseUrl = 'http://localhost:8000/api/v1';

  RoomsNotifier({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        super(const RoomsState());

  /// Update the base URL for the API.
  void setBaseUrl(String baseUrl) {
    _baseUrl = baseUrl;
  }

  /// Fetch available rooms from the server.
  Future<void> fetchRooms() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _httpClient.get(
        Uri.parse('$_baseUrl/rooms'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch rooms: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final List<Room> rooms;

      // Handle different response formats
      if (data is List) {
        // Array of rooms
        rooms = data.map((r) => Room.fromJson(r as Map<String, dynamic>)).toList();
      } else if (data is Map<String, dynamic>) {
        // Object with rooms array or room_ids
        if (data.containsKey('rooms')) {
          final roomsList = data['rooms'] as List;
          rooms = roomsList.map((r) => Room.fromJson(r as Map<String, dynamic>)).toList();
        } else if (data.containsKey('room_ids')) {
          // Simple list of room IDs
          final roomIds = data['room_ids'] as List;
          rooms = roomIds.map((id) => Room(id: id.toString(), name: id.toString())).toList();
        } else {
          // Treat keys as room IDs
          rooms = data.keys.map((id) => Room(id: id, name: id)).toList();
        }
      } else {
        throw Exception('Unexpected response format');
      }

      debugPrint('Rooms: Fetched ${rooms.length} rooms');
      state = state.copyWith(rooms: rooms, isLoading: false);
    } catch (e) {
      debugPrint('Rooms: Error fetching rooms: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh rooms list.
  Future<void> refresh() => fetchRooms();
}

/// Provider for rooms state.
final roomsProvider = StateNotifierProvider<RoomsNotifier, RoomsState>((ref) {
  return RoomsNotifier();
});

/// Provider for the currently selected room ID.
final selectedRoomProvider = StateProvider<String?>((ref) => null);
