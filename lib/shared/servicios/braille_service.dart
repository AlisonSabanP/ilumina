import 'package:braille_text/braille_text.dart';

/// Convierte texto a Braille Unicode para las etiquetas de Lumina.
///
/// Existe porque `BrailleConverter` de `braille_text` convierte a **espacio**
/// cualquier carácter que no esté en su tabla: las vocales acentuadas, la eñe y
/// las mayúsculas del español se perderían. Aquí se normaliza primero el texto
/// para que la etiqueta se lea entera.
///
/// La normalización también simplifica lo que se imprime: el Braille de grado 1
/// (letra a letra) no tiene una forma estándar de representar tildes en una
/// etiqueta corta, así que se eliminan en lugar de dejar huecos.
abstract final class BrailleService {
  /// Longitud máxima recomendada de una etiqueta.
  ///
  /// Una etiqueta larga no cabe en la mayoría de las piezas y se lee mal con el
  /// dedo. Se recorta por palabra completa.
  static const int maxLabelLength = 40;

  static final BrailleConverter _converter = BrailleConverter();

  /// Caracteres con tilde o diéresis, y su equivalente sin ella.
  static const Map<String, String> _accents = <String, String>{
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
    'Á': 'a', 'À': 'a', 'Ä': 'a', 'Â': 'a',
    'É': 'e', 'È': 'e', 'Ë': 'e', 'Ê': 'e',
    'Í': 'i', 'Ì': 'i', 'Ï': 'i', 'Î': 'i',
    'Ó': 'o', 'Ò': 'o', 'Ö': 'o', 'Ô': 'o',
    'Ú': 'u', 'Ù': 'u', 'Ü': 'u', 'Û': 'u',
    'Ñ': 'n', 'Ç': 'c',
  };

  /// Deja el texto en la forma que `braille_text` sabe convertir.
  ///
  /// Quita tildes y diéresis, pasa a minúsculas y descarta los caracteres que
  /// no tienen representación, para que no aparezcan como huecos.
  static String normalize(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final plain = _accents[char] ?? char.toLowerCase();
      // Solo letras, dígitos y los signos que la tabla de Braille contempla.
      if (RegExp(r'[a-z0-9 ,;:.!?()\-]').hasMatch(plain)) {
        buffer.write(plain);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Recorta a [max] sin partir la última palabra.
  static String truncate(String text, {int max = maxLabelLength}) {
    if (text.length <= max) return text;
    final cut = text.substring(0, max);
    final lastSpace = cut.lastIndexOf(' ');
    // Si no hay un espacio razonable, se corta tal cual.
    if (lastSpace < max ~/ 2) return cut.trim();
    return cut.substring(0, lastSpace).trim();
  }

  /// Texto listo para imprimir: normalizado y recortado.
  static String prepareLabel(String text, {int max = maxLabelLength}) =>
      truncate(normalize(text), max: max);

  /// Texto Braille Unicode (puntos en relieve) listo para la etiqueta.
  static String toBraille(String text) =>
      _converter.convertToBraille(normalize(text));

  /// Etiqueta a partir de un título: "Adaptador para sierra" ->
  /// "adaptador para sierra".
  ///
  /// Se usa para generar la etiqueta automáticamente cuando el usuario no ha
  /// escrito ninguna.
  static String labelFromTitle(String title) => prepareLabel(title);
}
