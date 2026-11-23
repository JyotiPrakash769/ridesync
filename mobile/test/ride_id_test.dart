import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/core/config/env.dart';
import 'package:ridesync/core/ride_id.dart';

void main() {
  group('normalizeRideId', () {
    test('uppercases and strips spaces/dashes', () {
      expect(normalizeRideId(' k7q-2mx '), 'K7Q2MX');
    });
    test('rejects ambiguous characters and wrong length', () {
      for (final bad in ['K7Q2M0', 'K7Q2MO', 'K7Q2M1', 'K7Q2MI', 'K7Q2ML', 'K7Q2M', 'K7Q2MXX', '']) {
        expect(normalizeRideId(bad), isNull, reason: bad);
      }
    });
  });

  group('parseRideIdFromLink', () {
    test('https app link', () {
      expect(parseRideIdFromLink('https://ridesync.app/join/K7Q2MX'), 'K7Q2MX');
      expect(parseRideIdFromLink('https://ridesync.app/join/k7q2mx/'), 'K7Q2MX');
    });
    test('join page on the backend host (QR default)', () {
      expect(parseRideIdFromLink('https://${Env.joinLinkHost}/join/K7Q2MX'), 'K7Q2MX');
      expect(Env.joinLinkHost, Uri.parse(Env.apiBaseUrl).host);
    });
    test('custom scheme fallback', () {
      expect(parseRideIdFromLink('ridesync://join/K7Q2MX'), 'K7Q2MX');
    });
    test('bare code', () {
      expect(parseRideIdFromLink('k7q2mx'), 'K7Q2MX');
    });
    test('rejects other hosts, paths and schemes', () {
      expect(parseRideIdFromLink('https://evil.example/join/K7Q2MX'), isNull);
      expect(parseRideIdFromLink('https://ridesync.app/ride/K7Q2MX'), isNull);
      expect(parseRideIdFromLink('ridesync://other/K7Q2MX'), isNull);
      expect(parseRideIdFromLink('http://ridesync.app/join/K7Q2MX'), isNull);
    });
  });
}
