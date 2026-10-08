import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  // 1. Separamos la baseUrl de la base de datos para que sea más fácil armar las rutas
  static const String baseUrl = 'https://plantatocancipa.site/api/v1';
  static const String database = 'db_logistica';

  // 2. ⚠️ RECUPERAMOS TU API KEY (estaba en tu código anterior)
  static const String apiKey = 'PlantaLogistica2026*';

  static final Map<String, String> _headers = {
    'Content-Type': 'application/json; charset=UTF-8',
    'x-api-key': apiKey, // ⚠️ CRÍTICO: Sin esto el servidor rechaza guardar
  };

  // ==========================================
  // CONSULTAR REGISTROS
  // ==========================================
  static Future<dynamic> consultar(String esquema, String tabla) async {
    final url = Uri.parse('$baseUrl/$database/consultar/$esquema/$tabla');
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Error al consultar: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // INSERTAR REGISTRO (Recuperado)
  // ==========================================
  static Future<bool> insertar(String esquema, String tabla, Map<String, dynamic> datos) async {
    final url = Uri.parse('$baseUrl/$database/insertar/$esquema/$tabla');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(datos),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        throw Exception('Error al insertar: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // ACTUALIZAR REGISTRO
  // ==========================================
  static Future<bool> actualizar(String esquema, String tabla, String idColumna, dynamic idValor, Map<String, dynamic> datos) async {
    final url = Uri.parse('$baseUrl/$database/actualizar/$esquema/$tabla/$idColumna/$idValor');
    try {
      final response = await http.put(
        url,
        headers: _headers,
        body: jsonEncode(datos),
      );
      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Error al actualizar: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // ELIMINAR REGISTRO
  // ==========================================
  static Future<bool> eliminar(String esquema, String tabla, String idColumna, dynamic idValor) async {
    final url = Uri.parse('$baseUrl/$database/eliminar/$esquema/$tabla/$idColumna/$idValor');
    try {
      final response = await http.delete(url, headers: _headers);
      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Error al eliminar: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  // ==========================================
  // SUBIR FOTO MULTIPLATAFORMA
  // ==========================================
  static Future<String?> subirFoto(String nombreCampo, Uint8List bytes, String nombreArchivo) async {
    try {
      final url = Uri.parse('$baseUrl/archivos/subir');
      var request = http.MultipartRequest('POST', url);

      // ⚠️ CRÍTICO: Añadimos el API Key a la petición Multipart
      request.headers['x-api-key'] = apiKey;

      request.files.add(http.MultipartFile.fromBytes(nombreCampo, bytes, filename: nombreArchivo));

      var streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201) {
        var response = await http.Response.fromStream(streamedResponse);
        var json = jsonDecode(response.body);

        // ✅ CORRECCIÓN: Leer el objeto 'urls' y buscar la llave exacta del campo
        if (json['exito'] == true && json['urls'] != null) {
          return json['urls'][nombreCampo];
        } else {
          print('Error lógico en JSON: $json');
        }
      } else {
        print('Error en servidor al subir foto: ${streamedResponse.statusCode}');
      }
    } catch (e) {
      print('Error al subir foto: $e');
    }
    return null;
  }

  // ==========================================
  // SUBIR IMAGEN (Atajo usado por el 5 Why)
  // ==========================================
  static Future<String?> subirImagen(Uint8List bytes) async {
    return await subirFoto('archivo', bytes, 'evidencia_${DateTime.now().millisecondsSinceEpoch}.jpg');
  }

  // ==========================================
  // 🤖 AUDITOR INTELIGENTE (GEMINI IA)
  // ==========================================
  static Future<bool> auditarConIA(String id) async {
    final url = Uri.parse('$baseUrl/$database/auditar/5why/$id');

    try {
      final response = await http.post(url, headers: _headers);

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Fallo en la auditoría IA (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Error de conexión con el Auditor IA: $e');
    }
  }
}