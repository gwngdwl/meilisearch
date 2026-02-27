import 'dart:io';
import 'dart:convert';

void main() async {
  final client = HttpClient();
  print('autoUncompress: ${client.autoUncompress}');

  // Test stats endpoint with HTTP/1.1 (same as our app uses)
  final req = await client
      .getUrl(Uri.parse('http://127.0.0.1:7700/indexes/seforim/stats'));
  print('Request accept-encoding: ${req.headers.value('accept-encoding')}');
  final res = await req.close();
  print('status: ${res.statusCode}');
  print('content-encoding: ${res.headers.value('content-encoding')}');
  print('transfer-encoding: ${res.headers.value('transfer-encoding')}');
  try {
    final body = await utf8.decoder.bind(res).join();
    print('body: $body');
    print('OK!');
  } catch (e) {
    print('ERROR: $e');
  }
  client.close();
}
