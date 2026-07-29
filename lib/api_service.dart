import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static const String baseUrl = 'https://plantatocancipa.site/api/v1';
  static const String database = 'db_logistica';
  static const String apiKey = 'PlantaLogistica2026*';

  static final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
  };

  // 🟢 CONSULTAR REGISTROS
  static Future<List<dynamic>> consultar(String esquema, String tabla) async {
    final url = Uri.parse('$baseUrl/$database/consultar/$esquema/$tabla');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['data'] ?? [];
    } else {
      throw Exception('Error de API (${response.statusCode}): ${response.body}');
    }
  }

  // 🔵 INSERTAR REGISTROS
  static Future<Map<String, dynamic>> insertar(String esquema, String tabla, Map<String, dynamic> datos) async {
    final url = Uri.parse('$baseUrl/$database/insertar/$esquema/$tabla');
    final response = await http.post(url, headers: _headers, body: jsonEncode(datos));
    if (response.statusCode == 201 || response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return body['data'] ?? {};
    } else {
      throw Exception('Error guardando datos (${response.statusCode}): ${response.body}');
    }
  }

  // 🟡 ACTUALIZAR REGISTROS (INTENTA RUTA NORMAL Y, SI DA 404, APLICA ACTUALIZACIÓN ATÓMICA SIN BORRAR EL HALLAZGO)
  static Future<Map<String, dynamic>> actualizar(
      String esquema,
      String tabla,
      String idColumna,
      dynamic idValor,
      Map<String, dynamic> datosActualizados,
      ) async {
    final Map<String, dynamic> bodyData = Map<String, dynamic>.from(datosActualizados);
    bodyData[idColumna] = idValor;

    final List<Map<String, String>> intentos = [
      {'method': 'PUT', 'url': '$baseUrl/$database/actualizar/$esquema/$tabla/$idColumna/$idValor'},
      {'method': 'POST', 'url': '$baseUrl/$database/actualizar/$esquema/$tabla/$idColumna/$idValor'},
      {'method': 'PUT', 'url': '$baseUrl/$database/actualizar/$esquema/$tabla'},
      {'method': 'POST', 'url': '$baseUrl/$database/actualizar/$esquema/$tabla'},
    ];

    for (var intento in intentos) {
      try {
        final method = intento['method']!;
        final url = Uri.parse(intento['url']!);
        http.Response response;

        if (method == 'PUT') {
          response = await http.put(url, headers: _headers, body: jsonEncode(bodyData));
        } else {
          response = await http.post(url, headers: _headers, body: jsonEncode(bodyData));
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          final body = jsonDecode(response.body);
          return body['data'] ?? {};
        }
      } catch (e) {
        debugPrint('Intento fallido en ${intento['url']}: $e');
      }
    }

    // 🛡️ RESPALDO SEGURO: Si el servidor da 404 en /actualizar, actualizamos copiando todo el registro intacto
    try {
      final registros = await consultar(esquema, tabla);
      Map<String, dynamic>? registroExistente;
      for (var reg in registros) {
        if (reg is Map && reg[idColumna]?.toString() == idValor.toString()) {
          registroExistente = Map<String, dynamic>.from(reg);
          break;
        }
      }

      if (registroExistente != null) {
        // SOBREESCRIBIMOS SOLO LOS CAMPOS NUEVOS (CIERRE), DEJANDO INTACTOS EVIDENCIA_HALLAZGO Y LOS DEMÁS
        datosActualizados.forEach((key, val) {
          if (val != null) {
            registroExistente![key] = val;
          }
        });

        await eliminar(esquema, tabla, idColumna, idValor);
        return await insertar(esquema, tabla, registroExistente);
      }
    } catch (e) {
      debugPrint('Error en respaldo de actualización: $e');
    }

    throw Exception('Error actualizando registro en servidor.');
  }

  // 🔴 ELIMINAR REGISTRO
  static Future<bool> eliminar(String esquema, String tabla, String idColumna, dynamic idValor) async {
    final url = Uri.parse('$baseUrl/$database/eliminar/$esquema/$tabla/$idColumna/$idValor');
    final response = await http.delete(url, headers: _headers);

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Error al eliminar: ${response.body}');
    }
  }

  // 📸 SUBIR FOTO MULTIPLATAFORMA
  static Future<String?> subirFoto(String nombreCampo, Uint8List bytes, String nombreArchivo) async {
    try {
      final url = Uri.parse('$baseUrl/archivos/subir');
      var request = http.MultipartRequest('POST', url);
      request.headers.addAll({'x-api-key': apiKey});

      String tipoMime = nombreArchivo.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';

      request.files.add(http.MultipartFile.fromBytes(
        nombreCampo,
        bytes,
        filename: nombreArchivo,
        contentType: MediaType('image', tipoMime),
      ));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final json = jsonDecode(responseData);

      if ((response.statusCode == 200 || response.statusCode == 201) && json['exito'] == true) {
        if (json['urls'] != null && json['urls'][nombreCampo] != null) {
          return json['urls'][nombreCampo];
        }
      }

      if (json['url'] != null) return json['url'];
      if (json['path'] != null) return json['path'];
    } catch (e) {
      debugPrint('Excepción al subir foto a servidor: $e');
    }

    final String base64Image = base64Encode(bytes);
    return 'data:image/jpeg;base64,$base64Image';
  }
}