import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'route_models.dart';

class RoutingFailure implements Exception {
  const RoutingFailure(this.message);
  final String message;
}

abstract class RoadRouter {
  Future<RoadRoute> route(List<RouteStop> stops);
}

class OsrmRouter implements RoadRouter {
  OsrmRouter({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'ROUTING_BASE_URL',
      defaultValue: 'https://router.project-osrm.org',
    ),
  }) : client = client ?? http.Client(),
       ownsClient = client == null;
  final http.Client client;
  final bool ownsClient;
  final String baseUrl;
  DateTime? lastRequest;
  final _active = <Completer<void>>{};

  Future<http.Response> _response(Uri endpoint) async {
    final abort = Completer<void>();
    _active.add(abort);
    try {
      return await (() async {
        final request =
            http.AbortableRequest('GET', endpoint, abortTrigger: abort.future)
              ..headers.addAll({
                'User-Agent': 'Fieldnotes/1.0',
                'Accept': 'application/json',
              });
        final response = await client.send(request);
        if (response.statusCode != 200 && response.statusCode != 400) {
          await response.stream.listen((_) {}).cancel();
          return http.Response('', response.statusCode);
        }
        const limit = 10 * 1024 * 1024;
        if ((response.contentLength ?? 0) > limit) {
          await response.stream.listen((_) {}).cancel();
          throw const RoutingFailure(
            'This route is too large. Try fewer or closer stops.',
          );
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > limit) {
            throw const RoutingFailure(
              'This route is too large. Try fewer or closer stops.',
            );
          }
          bytes.add(chunk);
        }
        return http.Response.bytes(
          bytes.takeBytes(),
          response.statusCode,
          headers: response.headers,
        );
      })().timeout(const Duration(seconds: 20));
    } finally {
      if (!abort.isCompleted) abort.complete();
      _active.remove(abort);
    }
  }

  @override
  Future<RoadRoute> route(List<RouteStop> stops) async {
    if (stops.length < 2 || stops.length > 25 || stops.any((s) => !s.valid)) {
      throw const RoutingFailure('Choose between 2 and 25 valid route stops.');
    }
    final now = DateTime.now();
    if (lastRequest != null &&
        now.difference(lastRequest!) < const Duration(seconds: 1)) {
      throw const RoutingFailure(
        'Please wait a moment before calculating again.',
      );
    }
    lastRequest = now;
    final coordinates = stops
        .map((s) => '${s.longitude},${s.latitude}')
        .join(';');
    final endpoint =
        Uri.parse(
          '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/route/v1/driving/$coordinates',
        ).replace(
          queryParameters: {
            'overview': 'full',
            'geometries': 'geojson',
            'steps': 'false',
            'alternatives': 'false',
          },
        );
    try {
      final response = await _response(endpoint);
      if (response.statusCode == 429) {
        throw const RoutingFailure(
          'The routing service is busy. Wait a little and try again.',
        );
      }
      if (response.statusCode != 200 && response.statusCode != 400) {
        throw const RoutingFailure(
          'The routing service is unavailable. Your saved plan is still available.',
        );
      }
      if (response.bodyBytes.length > 10 * 1024 * 1024) {
        throw const RoutingFailure(
          'This route is too large. Try fewer or closer stops.',
        );
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['code'] == 'NoRoute' || data['code'] == 'NoSegment') {
        throw const RoutingFailure(
          'No driving route connects these stops. Try moving them closer to accessible roads.',
        );
      }
      if (response.statusCode != 200) {
        throw const RoutingFailure(
          'The routing service could not process these stops. Try moving them closer to roads.',
        );
      }
      if (data['code'] != 'Ok' ||
          data['routes'] is! List ||
          (data['routes'] as List).isEmpty) {
        throw const FormatException('Missing route');
      }
      final best = (data['routes'] as List).first as Map<String, dynamic>;
      return RoadRoute(
        geometry: best['geometry'] as Map<String, dynamic>,
        distanceMeters: (best['distance'] as num).toDouble(),
        durationSeconds: (best['duration'] as num).toDouble(),
        stopsSignature: stopSignature(stops),
      );
    } on RoutingFailure {
      rethrow;
    } on TimeoutException {
      throw const RoutingFailure(
        'Routing timed out. Try again when your connection is available.',
      );
    } on http.ClientException {
      throw const RoutingFailure(
        'Could not connect to routing. You can still save or edit the plan offline.',
      );
    } catch (_) {
      throw const RoutingFailure(
        'The routing service returned an unreadable route. Try again later.',
      );
    }
  }

  void close() {
    for (final request in _active.toList()) {
      if (!request.isCompleted) request.complete();
    }
    if (ownsClient) client.close();
  }
}
