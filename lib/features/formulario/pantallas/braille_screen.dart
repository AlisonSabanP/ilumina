import 'package:braille_text/braille_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/servicios/braille_service.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../modelos/formulario_provider.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';

/// Generador de etiquetas en Braille.
///
/// Usa el paquete `braille_text`:
///  * [BrailleText] dibuja el Braille y, al deslizar el dedo por encima, emite
///    una vibración corta por cada carácter, de modo que el usuario puede
///    "leer" la etiqueta con el dedo antes de imprimirla.
///  * [BrailleService] normaliza antes el texto (quita tildes y mayúsculas) y
///    lo recorta, porque el conversor del paquete convierte a espacio todo lo
///    que no esté en su tabla.
///
/// El texto que se ve aquí es el mismo que se graba en relieve en la pieza: se
/// añade al prompt de generación, así que la etiqueta nace ya integrada en el
/// objeto y no hay que imprimirla aparte.
///
/// El tamaño de la fuente es ajustable porque el Braille en pantalla debe
/// poder leerse con el dedo: a mayor tamaño, más separación entre puntos.
class BrailleScreen extends StatefulWidget {
  const BrailleScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const BrailleScreen(),
      );

  @override
  State<BrailleScreen> createState() => _BrailleScreenState();
}

class _BrailleScreenState extends State<BrailleScreen> {
  final TextEditingController _controller = TextEditingController();

  /// Tamaño de fuente del Braille, en puntos lógicos.
  double _textSize = 40;

  static const double _minSize = 16;
  static const double _maxSize = 96;

  @override
  void initState() {
    super.initState();
    final saved = context.read<FormularioProvider>().brailleText;
    if (saved.isNotEmpty) {
      _controller.text = saved;
    }
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    context.read<FormularioProvider>().setBrailleText(_controller.text);
    setState(() {});
  }

  /// Texto normalizado (sin tildes) y recortado, tal y como se imprimirá.
  String get _labelText => BrailleService.prepareLabel(_controller.text);

  String get _brailleOutput => BrailleService.toBraille(_controller.text);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _brailleOutput));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Braille copiado al portapapeles')),
    );
  }

  Future<void> _share() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Etiqueta Lumina\n\n'
            'Texto: $text\n'
            'Braille: $_brailleOutput\n\n'
            'Lumina la graba en relieve en la pieza (punto de 1,5 mm).',
        subject: 'Etiqueta en Braille generada con Lumina',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final text = _controller.text;
    final hasText = text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Etiqueta en Braille')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const LuminaPageHeader(
            title: 'Etiqueta en Braille',
            subtitle:
                'Escribe el texto y desliza el dedo por la vista previa para notar la vibración de cada carácter.',
            icon: Icons.dialpad,
          ),
          LuminaInfoBanner(
            message: hasText
                ? 'Esta etiqueta se graba en relieve en la pieza. Desliza el dedo por la vista previa para notar cada carácter.'
                : 'Escribe algo para generar la etiqueta.',
            icon: hasText ? Icons.vibration : Icons.edit_note,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            maxLength: 40,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Texto de la etiqueta',
              helperText:
                  'Se admiten letras, números y signos básicos. Las tildes y las '
                  'mayúsculas se simplifican. Máximo 40 caracteres.',
              prefixIcon: Icon(Icons.text_fields),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LuminaSectionCard(
            title: 'Tamaño del Braille',
            subtitle:
                'Aumenta el tamaño si vas a leer la etiqueta con el dedo en la pantalla.',
            leadingIcon: Icons.format_size,
            child: Semantics(
              slider: true,
              label: 'Tamaño del Braille',
              value: '${_textSize.round()} puntos',
              child: Slider(
                value: _textSize,
                min: _minSize,
                max: _maxSize,
                divisions: ((_maxSize - _minSize) / 4).round(),
                label: '${_textSize.round()} pt',
                onChanged: (value) => setState(() => _textSize = value),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LuminaSectionCard(
            title: 'Vista previa',
            subtitle: 'Braille Unicode generado a partir del texto.',
            leadingIcon: Icons.visibility,
            child: hasText
                ? Semantics(
                    label:
                        'Vista previa en Braille de: $text. Desliza el dedo por encima para notar la vibración.',
                    excludeSemantics: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.cardRadius,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: BrailleText(
                          text: _labelText,
                          textSize: _textSize,
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'Aún no hay texto.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LuminaSectionCard(
            title: 'Texto Braille (seleccionable)',
            subtitle:
                'Cópialo o compártelo si quieres grabarlo por tu cuenta.',
            leadingIcon: Icons.code,
            child: SelectableText(
              hasText ? _brailleOutput : '—',
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          AccessibleButton(
            label: 'Copiar Braille',
            icon: Icons.copy,
            pictogram: Icons.copy,
            isPrimary: false,
            onPressed: hasText ? _copy : null,
            hint: 'Copia los caracteres Braille al portapapeles',
          ),
          SizedBox(height: a11y.controlGap),
          AccessibleButton(
            label: 'Compartir etiqueta',
            icon: Icons.share,
            pictogram: Icons.share,
            onPressed: hasText ? _share : null,
            hint: 'Comparte el texto y su Braille con otra aplicación',
          ),
          const SizedBox(height: AppSpacing.xl),
          LuminaInfoBanner(
            message:
                'Al generar el modelo, la etiqueta se pide con relieve de 1,5 mm '
                'de altura y 2,5 mm entre puntos, que son las medidas que la '
                'hacen legible con el dedo.',
            icon: Icons.print,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
