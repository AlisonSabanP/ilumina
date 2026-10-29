import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Punto 3D mínimo. Se usa en lugar de `vector_math` para no arrastrar una
/// dependencia solo por construir mallas sencillas.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);
  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 get normalized {
    final l = length;
    if (l == 0) return const Vec3(0, 0, 1);
    return Vec3(x / l, y / l, z / l);
  }
}

/// Construye mallas triangulares y las serializa a **STL binario**.
///
/// Se eligió STL binario (y no glTF) porque es lo que espera cualquier
/// laminador —Cura, PrusaSlicer, Bambu Studio— sin conversiones, y porque el
/// archivo resultante es un volcado directo de triángulos: no hace falta
/// escribir un exportador de materiales, escenas ni UVs.
///
/// Convención de coordenadas: **Z es la altura**, el plano de la cama de
/// impresión es XY y todas las piezas se generan con la base en `z = 0`, listas
/// para laminar sin reorientar.
///
/// Todas las primitivas emiten triángulos con la normal hacia fuera, que es lo
/// que exige el formato: si el sentido de giro fuese el contrario, el laminador
/// interpretaría la pieza del revés.
class MeshBuilder {
  final List<double> _vertices = <double>[];

  int get triangleCount => _vertices.length ~/ 9;

  bool get isEmpty => _vertices.isEmpty;

  /// Añade un triángulo con los vértices en sentido antihorario visto desde
  /// fuera (regla de la mano derecha).
  void addTriangle(Vec3 a, Vec3 b, Vec3 c) {
    _vertices
      ..add(a.x)
      ..add(a.y)
      ..add(a.z)
      ..add(b.x)
      ..add(b.y)
      ..add(b.z)
      ..add(c.x)
      ..add(c.y)
      ..add(c.z);
  }

  /// Cuadrilátero convexo `a-b-c-d` (en orden) como dos triángulos.
  void _quad(Vec3 a, Vec3 b, Vec3 c, Vec3 d) {
    addTriangle(a, b, c);
    addTriangle(a, c, d);
  }

  // --- Primitivas ------------------------------------------------------------

  /// Caja alineada con los ejes, definida por dos esquinas opuestas.
  void addBox(Vec3 min, Vec3 max) {
    final p000 = Vec3(min.x, min.y, min.z);
    final p100 = Vec3(max.x, min.y, min.z);
    final p110 = Vec3(max.x, max.y, min.z);
    final p010 = Vec3(min.x, max.y, min.z);
    final p001 = Vec3(min.x, min.y, max.z);
    final p101 = Vec3(max.x, min.y, max.z);
    final p111 = Vec3(max.x, max.y, max.z);
    final p011 = Vec3(min.x, max.y, max.z);

    _quad(p000, p010, p110, p100); // inferior (-Z)
    _quad(p001, p101, p111, p011); // superior (+Z)
    _quad(p000, p100, p101, p001); // frontal (-Y)
    _quad(p010, p011, p111, p110); // trasera (+Y)
    _quad(p000, p001, p011, p010); // izquierda (-X)
    _quad(p100, p110, p111, p101); // derecha (+X)
  }

  /// Cilindro macizo de eje Z, con tapas.
  void addCylinderZ({
    required double cx,
    required double cy,
    required double z0,
    required double z1,
    required double radius,
    int segments = 48,
  }) {
    if (radius <= 0 || z1 <= z0) return;
    final bottomCenter = Vec3(cx, cy, z0);
    final topCenter = Vec3(cx, cy, z1);

    for (var i = 0; i < segments; i++) {
      final a0 = 2 * math.pi * i / segments;
      final a1 = 2 * math.pi * (i + 1) / segments;
      final b0 = Vec3(cx + radius * math.cos(a0), cy + radius * math.sin(a0), z0);
      final b1 = Vec3(cx + radius * math.cos(a1), cy + radius * math.sin(a1), z0);
      final t0 = Vec3(cx + radius * math.cos(a0), cy + radius * math.sin(a0), z1);
      final t1 = Vec3(cx + radius * math.cos(a1), cy + radius * math.sin(a1), z1);

      _quad(b0, b1, t1, t0);            // lateral
      addTriangle(topCenter, t0, t1);    // tapa superior (+Z)
      addTriangle(bottomCenter, b1, b0); // tapa inferior (-Z)
    }
  }

  /// Tubo (cilindro hueco) de eje Z con caras interior y exterior y anillos
  /// superior e inferior.
  ///
  /// Es la forma base de los engrosadores de mango: el agujero interior es
  /// geometría real, no un efecto, así que la pieza sale lista para imprimir.
  void addTubeZ({
    required double cx,
    required double cy,
    required double z0,
    required double z1,
    required double outerRadius,
    required double innerRadius,
    int segments = 64,
  }) {
    if (outerRadius <= innerRadius || innerRadius < 0 || z1 <= z0) return;

    for (var i = 0; i < segments; i++) {
      final a0 = 2 * math.pi * i / segments;
      final a1 = 2 * math.pi * (i + 1) / segments;

      final ob0 = Vec3(cx + outerRadius * math.cos(a0), cy + outerRadius * math.sin(a0), z0);
      final ob1 = Vec3(cx + outerRadius * math.cos(a1), cy + outerRadius * math.sin(a1), z0);
      final ot0 = Vec3(cx + outerRadius * math.cos(a0), cy + outerRadius * math.sin(a0), z1);
      final ot1 = Vec3(cx + outerRadius * math.cos(a1), cy + outerRadius * math.sin(a1), z1);

      final ib0 = Vec3(cx + innerRadius * math.cos(a0), cy + innerRadius * math.sin(a0), z0);
      final ib1 = Vec3(cx + innerRadius * math.cos(a1), cy + innerRadius * math.sin(a1), z0);
      final it0 = Vec3(cx + innerRadius * math.cos(a0), cy + innerRadius * math.sin(a0), z1);
      final it1 = Vec3(cx + innerRadius * math.cos(a1), cy + innerRadius * math.sin(a1), z1);

      _quad(ob0, ob1, ot1, ot0); // pared exterior, normal hacia fuera
      _quad(ib0, it0, it1, ib1); // pared interior, normal hacia el eje
      _quad(ib0, ib1, ob1, ob0); // anillo inferior (-Z)
      _quad(it0, ot0, ot1, it1); // anillo superior (+Z)
    }
  }

  /// Media esfera (cúpula) apoyada en `z0`, con la base cerrada.
  ///
  /// Es la forma correcta de un punto Braille impreso: la punta redondeada se
  /// lee con el dedo sin raspar y el apoyo plano se adhiere a la placa.
  void addDome({
    required double cx,
    required double cy,
    required double z0,
    required double radius,
    int segments = 16,
    int rings = 6,
  }) {
    if (radius <= 0) return;
    final baseCenter = Vec3(cx, cy, z0);

    for (var r = 0; r < rings; r++) {
      final phi0 = (math.pi / 2) * r / rings;
      final phi1 = (math.pi / 2) * (r + 1) / rings;
      final r0 = radius * math.cos(phi0);
      final r1 = radius * math.cos(phi1);
      final h0 = radius * math.sin(phi0);
      final h1 = radius * math.sin(phi1);

      for (var i = 0; i < segments; i++) {
        final a0 = 2 * math.pi * i / segments;
        final a1 = 2 * math.pi * (i + 1) / segments;

        final p0 = Vec3(cx + r0 * math.cos(a0), cy + r0 * math.sin(a0), z0 + h0);
        final p1 = Vec3(cx + r0 * math.cos(a1), cy + r0 * math.sin(a1), z0 + h0);
        final p2 = Vec3(cx + r1 * math.cos(a1), cy + r1 * math.sin(a1), z0 + h1);
        final p3 = Vec3(cx + r1 * math.cos(a0), cy + r1 * math.sin(a0), z0 + h1);

        if (r == rings - 1) {
          addTriangle(p0, p1, p2); // anillo que cierra en el polo
        } else {
          _quad(p0, p1, p2, p3);
        }
      }
    }

    // Base plana, para que la cúpula sea un sólido cerrado.
    for (var i = 0; i < segments; i++) {
      final a0 = 2 * math.pi * i / segments;
      final a1 = 2 * math.pi * (i + 1) / segments;
      final p0 = Vec3(cx + radius * math.cos(a0), cy + radius * math.sin(a0), z0);
      final p1 = Vec3(cx + radius * math.cos(a1), cy + radius * math.sin(a1), z0);
      addTriangle(baseCenter, p1, p0);
    }
  }

  /// Banda curva (casquete cilíndrico) entre `startAngle` y `endAngle`.
  ///
  /// Es la forma de las férulas: una pared que abraza el miembro. Al dejar
  /// hueco entre bandas consecutivas se obtiene ventilación real sin necesidad
  /// de restar geometría.
  void addArcBand({
    required double cx,
    required double cy,
    required double z0,
    required double z1,
    required double outerRadius,
    required double innerRadius,
    required double startAngle,
    required double endAngle,
    int segments = 24,
  }) {
    if (outerRadius <= innerRadius || z1 <= z0 || endAngle <= startAngle) return;

    for (var i = 0; i < segments; i++) {
      final a0 = startAngle + (endAngle - startAngle) * i / segments;
      final a1 = startAngle + (endAngle - startAngle) * (i + 1) / segments;

      final ob0 = Vec3(cx + outerRadius * math.cos(a0), cy + outerRadius * math.sin(a0), z0);
      final ob1 = Vec3(cx + outerRadius * math.cos(a1), cy + outerRadius * math.sin(a1), z0);
      final ot0 = Vec3(cx + outerRadius * math.cos(a0), cy + outerRadius * math.sin(a0), z1);
      final ot1 = Vec3(cx + outerRadius * math.cos(a1), cy + outerRadius * math.sin(a1), z1);

      final ib0 = Vec3(cx + innerRadius * math.cos(a0), cy + innerRadius * math.sin(a0), z0);
      final ib1 = Vec3(cx + innerRadius * math.cos(a1), cy + innerRadius * math.sin(a1), z0);
      final it0 = Vec3(cx + innerRadius * math.cos(a0), cy + innerRadius * math.sin(a0), z1);
      final it1 = Vec3(cx + innerRadius * math.cos(a1), cy + innerRadius * math.sin(a1), z1);

      _quad(ob0, ob1, ot1, ot0); // exterior
      _quad(ib0, it0, it1, ib1); // interior
      _quad(ib0, ib1, ob1, ob0); // canto inferior
      _quad(it0, ot0, ot1, it1); // canto superior
    }

    // Tapas laterales de la banda, para cerrar el sólido.
    final obs = Vec3(cx + outerRadius * math.cos(startAngle), cy + outerRadius * math.sin(startAngle), z0);
    final ots = Vec3(cx + outerRadius * math.cos(startAngle), cy + outerRadius * math.sin(startAngle), z1);
    final ibs = Vec3(cx + innerRadius * math.cos(startAngle), cy + innerRadius * math.sin(startAngle), z0);
    final its = Vec3(cx + innerRadius * math.cos(startAngle), cy + innerRadius * math.sin(startAngle), z1);
    _quad(ibs, obs, ots, its);

    final obe = Vec3(cx + outerRadius * math.cos(endAngle), cy + outerRadius * math.sin(endAngle), z0);
    final ote = Vec3(cx + outerRadius * math.cos(endAngle), cy + outerRadius * math.sin(endAngle), z1);
    final ibe = Vec3(cx + innerRadius * math.cos(endAngle), cy + innerRadius * math.sin(endAngle), z0);
    final ite = Vec3(cx + innerRadius * math.cos(endAngle), cy + innerRadius * math.sin(endAngle), z1);
    _quad(ibe, ite, ote, obe);
  }

  // --- Serialización ---------------------------------------------------------

  /// Serializa la malla a STL binario.
  ///
  /// Formato: cabecera de 80 bytes + contador `uint32` + 50 bytes por
  /// triángulo (normal `float32 x3`, vértices `float32 x9`, atributo `uint16`).
  /// La normal se calcula del producto vectorial; si el triángulo es
  /// degenerado se escribe la normal cero, que el estándar admite.
  Uint8List toBinaryStl({String header = 'Lumina'}) {
    const int triangleBytes = 50;
    final count = triangleCount;
    final bytes = Uint8List(84 + count * triangleBytes);
    final data = ByteData.sublistView(bytes);

    final headerBytes = Uint8List.fromList(header.codeUnits);
    final headerLength = math.min(80, headerBytes.length);
    bytes.setRange(0, headerLength, headerBytes);

    data.setUint32(80, count, Endian.little);

    var offset = 84;
    for (var t = 0; t < count; t++) {
      final base = t * 9;
      final a = Vec3(_vertices[base], _vertices[base + 1], _vertices[base + 2]);
      final b = Vec3(_vertices[base + 3], _vertices[base + 4], _vertices[base + 5]);
      final c = Vec3(_vertices[base + 6], _vertices[base + 7], _vertices[base + 8]);

      final normal = (b - a).cross(c - a).normalized;
      data.setFloat32(offset, normal.x, Endian.little);
      data.setFloat32(offset + 4, normal.y, Endian.little);
      data.setFloat32(offset + 8, normal.z, Endian.little);

      data.setFloat32(offset + 12, a.x, Endian.little);
      data.setFloat32(offset + 16, a.y, Endian.little);
      data.setFloat32(offset + 20, a.z, Endian.little);
      data.setFloat32(offset + 24, b.x, Endian.little);
      data.setFloat32(offset + 28, b.y, Endian.little);
      data.setFloat32(offset + 32, b.z, Endian.little);
      data.setFloat32(offset + 36, c.x, Endian.little);
      data.setFloat32(offset + 40, c.y, Endian.little);
      data.setFloat32(offset + 44, c.z, Endian.little);
      data.setUint16(offset + 48, 0, Endian.little);

      offset += triangleBytes;
    }

    return bytes;
  }

  /// Serializa la malla a **glTF binario (GLB)**.
  ///
  /// Se emite además del STL porque los dos formatos sirven a fines distintos:
  /// el STL es lo que abre el laminador, y el GLB es lo que el visor 3D
  /// (`power3d`, basado en Babylon.js) sabe pintar con materiales y luces. Con
  /// ambos, Lumina puede generar, ver y descargar una pieza sin depender de
  /// ningún servicio externo ni de un modelo de ejemplo empaquetado.
  ///
  /// La geometría se escribe **sin índices** (tres vértices por triángulo): es
  /// glTF válido y evita tener que construir y alinear un búfer de índices.
  Uint8List toGlb({String name = 'Lumina'}) {
    final count = triangleCount;
    if (count == 0) {
      throw StateError('No se puede exportar una malla vacía.');
    }

    final vertexCount = count * 3;
    final positions = Float32List(vertexCount * 3);
    final normals = Float32List(vertexCount * 3);

    for (var t = 0; t < count; t++) {
      final base = t * 9;
      final a = Vec3(_vertices[base], _vertices[base + 1], _vertices[base + 2]);
      final b = Vec3(_vertices[base + 3], _vertices[base + 4], _vertices[base + 5]);
      final c = Vec3(_vertices[base + 6], _vertices[base + 7], _vertices[base + 8]);
      final normal = (b - a).cross(c - a).normalized;

      for (var v = 0; v < 3; v++) {
        final vertex = v == 0 ? a : (v == 1 ? b : c);
        final offset = (t * 3 + v) * 3;
        positions[offset] = vertex.x;
        positions[offset + 1] = vertex.y;
        positions[offset + 2] = vertex.z;
        normals[offset] = normal.x;
        normals[offset + 1] = normal.y;
        normals[offset + 2] = normal.z;
      }
    }

    var minX = positions[0], minY = positions[1], minZ = positions[2];
    var maxX = minX, maxY = minY, maxZ = minZ;
    for (var i = 0; i < vertexCount; i++) {
      final x = positions[i * 3];
      final y = positions[i * 3 + 1];
      final z = positions[i * 3 + 2];
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      minZ = math.min(minZ, z);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
      maxZ = math.max(maxZ, z);
    }

    final positionsBytes = positions.buffer.asUint8List();
    final normalsBytes = normals.buffer.asUint8List();
    final binaryChunk = Uint8List(positionsBytes.length + normalsBytes.length);
    binaryChunk.setRange(0, positionsBytes.length, positionsBytes);
    binaryChunk.setRange(positionsBytes.length, binaryChunk.length, normalsBytes);

    // Se rellena a múltiplo de 4 porque glTF exige que los fragmentos del
    // contenedor estén alineados; el relleno va con ceros y se declara en la
    // longitud del propio fragmento.
    final paddedBinary = _pad4(binaryChunk);

    final json = <String, dynamic>{
      'asset': <String, dynamic>{'version': '2.0', 'generator': 'Lumina'},
      'scene': 0,
      'scenes': <dynamic>[
        <String, dynamic>{'nodes': <int>[0], 'name': 'Escena'},
      ],
      'nodes': <dynamic>[
        <String, dynamic>{'mesh': 0, 'name': name},
      ],
      'meshes': <dynamic>[
        <String, dynamic>{
          'name': name,
          'primitives': <dynamic>[
            <String, dynamic>{
              'attributes': <String, dynamic>{'POSITION': 0, 'NORMAL': 1},
              'material': 0,
              'mode': 4, // TRIANGLES
            },
          ],
        },
      ],
      'materials': <dynamic>[
        <String, dynamic>{
          'name': 'Lumina',
          'pbrMetallicRoughness': <String, dynamic>{
            'baseColorFactor': <double>[0.17, 0.37, 0.54, 1.0],
            'metallicFactor': 0.0,
            'roughnessFactor': 0.65,
          },
          'doubleSided': true,
        },
      ],
      'bufferViews': <dynamic>[
        <String, dynamic>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': positionsBytes.length,
          'target': 34962, // ARRAY_BUFFER
        },
        <String, dynamic>{
          'buffer': 0,
          'byteOffset': positionsBytes.length,
          'byteLength': normalsBytes.length,
          'target': 34962,
        },
      ],
      'accessors': <dynamic>[
        <String, dynamic>{
          'bufferView': 0,
          'componentType': 5126, // FLOAT
          'count': vertexCount,
          'type': 'VEC3',
          'min': <double>[minX, minY, minZ],
          'max': <double>[maxX, maxY, maxZ],
        },
        <String, dynamic>{
          'bufferView': 1,
          'componentType': 5126,
          'count': vertexCount,
          'type': 'VEC3',
        },
      ],
      'buffers': <dynamic>[
        <String, dynamic>{'byteLength': paddedBinary.length},
      ],
    };

    final jsonBytes = _pad4(
      Uint8List.fromList(
        const Utf8Encoder().convert(jsonEncode(json)),
      ),
      padWithSpace: true,
    );

    final totalLength = 12 + 8 + jsonBytes.length + 8 + paddedBinary.length;
    final glb = Uint8List(totalLength);
    final view = ByteData.sublistView(glb);

    view.setUint32(0, 0x46546C67, Endian.little); // "glTF"
    view.setUint32(4, 2, Endian.little);
    view.setUint32(8, totalLength, Endian.little);

    view.setUint32(12, jsonBytes.length, Endian.little);
    view.setUint32(16, 0x4E4F534A, Endian.little); // "JSON"
    glb.setRange(20, 20 + jsonBytes.length, jsonBytes);

    final binaryHeader = 20 + jsonBytes.length;
    view.setUint32(binaryHeader, paddedBinary.length, Endian.little);
    view.setUint32(binaryHeader + 4, 0x004E4942, Endian.little); // "BIN"
    glb.setRange(
      binaryHeader + 8,
      binaryHeader + 8 + paddedBinary.length,
      paddedBinary,
    );

    return glb;
  }

  /// Rellena hasta el siguiente múltiplo de 4 bytes.
  static Uint8List _pad4(Uint8List data, {bool padWithSpace = false}) {
    final remainder = data.length % 4;
    if (remainder == 0) return data;
    final padding = 4 - remainder;
    final padded = Uint8List(data.length + padding);
    padded.setRange(0, data.length, data);
    if (padWithSpace) {
      for (var i = data.length; i < padded.length; i++) {
        padded[i] = 0x20; // Espacio: relleno válido en el fragmento JSON.
      }
    }
    return padded;
  }
}
