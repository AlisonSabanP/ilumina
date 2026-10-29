import 'package:braille_text/braille_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/servicios/braille_service.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';
import '../../generacion3d/pantallas/generacion_screen.dart';
import '../../generacion3d/providers/generation_provider.dart';
import '../../generacion3d/servicios/local_generator_service.dart';
import '../../visor3d/pantallas/visor_modelo_screen.dart';
import '../modelos/formulario_provider.dart';

/// Generador de etiquetas en Braille.
///
/// Es la pantalla del perfil visual: quien no ve el objeto necesita una
/// etiqueta que pueda leer con el dedo, y aquí se escribe, se ve en Braille y se
/// convierte en una **pieza imprimible aparte**.
///
/// La etiqueta no se graba sobre la pieza principal: se imprime sola, para
/// pegar o colgar del objeto que identifica. Se crea desde esta pantalla o
/// eligiendo la rama visual del formulario (ambas construyen la misma placa).
///
/// Usa el paquete `braille_text`:
///  * [BrailleText] dibuja el Braille y, al deslizar el dedo por encima, emite
///    una vibración corta por cada carácter, de modo que el usuario puede
///    "leer" la etiqueta antes de imprimirla.
///  * [BrailleService] normaliza antes el texto (quita tildes y mayúsculas) y
///    lo recorta, porque el conversor del paquete convierte a espacio todo lo
///    que no esté en su tabla.
///
/// La vista previa se dibuja siempre con el texto ya normalizado, y si no queda
/// nada que mostrar se avisa en lugar de dejar el hueco en blanco: el error
/// original era pasar a [BrailleText] un texto que la normalización había
/// vaciado, con lo que parecía que la etiqueta "no funcionaba".
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
  double _textSize = 48;

  static const double _minSize = 24;
  static const double _maxSize = 120;

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

  /// `true` cuando hay algo que se puede imprimir de verdad.
  ///
  /// Un texto compuesto solo de signos no representables se normaliza a cadena
  /// vacía: en ese caso no hay etiqueta que generar.
  bool get _hasPrintableLabel => _labelText.isNotEmpty;

  String get _brailleOutput =>
      _hasPrintableLabel ? BrailleService.toBraille(_controller.text) : '';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _brailleOutput));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Braille copiado al portapapeles')),
    );
  }

  Future<void> _share() async {
    if (!_hasPrintableLabel) return;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Etiqueta Lumina\n\n'
            'Texto: $_labelText\n'
            'Braille: $_brailleOutput\n\n'
            'Lumina puede imprimirla como pieza aparte, con puntos de '
            '${LocalGeneratorService.brailleDotHeight} mm de altura.',
        subject: 'Etiqueta en Braille generada con Lumina',
      ),
    );
  }

  /// Crea la etiqueta como pieza imprimible y abre el visor.
  ///
  /// Construye el STL con los puntos en relieve y lo muestra igual que
  /// cualquier otra pieza. La etiqueta nunca se añade a la pieza principal: se
  /// imprime suelta.
  Future<void> _createPiece() async {
    final generation = context.read<GenerationProvider>();
    final navigator = Navigator.of(context);

    await generation.generateBrailleLabel(
      _labelText,
      title: 'Etiqueta Braille · $_labelText',
    );

    if (!mounted) return;
    final model = generation.model;
    if (model == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            generation.error?.message ??
                'No se pudo crear la etiqueta. Inténtalo otra vez.',
          ),
        ),
      );
      return;
    }
    navigator.push(VisorModeloScreen.route(model));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a11y = AccessibilityProvider.of(context);
    final hasText = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Etiqueta en Braille')),
      floatingActionButton: const AccessibilityFab(heroTag: 'braille.a11y'),
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
                ? 'Esta etiqueta se imprime en relieve. Desliza el dedo por la vista previa para notar cada carácter.'
                : 'Escribe algo para generar la etiqueta.',
            icon: hasText ? Icons.vibration : Icons.edit_note,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            maxLength: BrailleService.maxLabelLength,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Texto de la etiqueta',
              helperText:
                  'Se admiten letras, números y signos básicos. Las tildes y las '
                  'mayúsculas se simplifican.',
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
              child: ExcludeSemantics(
                child: Slider(
                  value: _textSize,
                  min: _minSize,
                  max: _maxSize,
                  divisions: ((_maxSize - _minSize) / 8).round(),
                  label: '${_textSize.round()} pt',
                  onChanged: (value) => setState(() => _textSize = value),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LuminaSectionCard(
            title: 'Vista previa',
            subtitle: 'Braille Unicode generado a partir del texto.',
            leadingIcon: Icons.visibility,
            child: _hasPrintableLabel
                ? Semantics(
                    label:
                        'Vista previa en Braille de: $_labelText. Desliza el dedo por encima para notar la vibración.',
                    excludeSemantics: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.cardRadius,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: BrailleText(
                            text: _labelText,
                            textSize: _textSize,
                          ),
                        ),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      hasText
                          ? 'Ese texto no se puede convertir: prueba con letras y '
                              'números.'
                          : 'Aún no hay texto.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LuminaSectionCard(
            title: 'Texto Braille (seleccionable)',
            subtitle: 'Cópialo o compártelo si quieres grabarlo por tu cuenta.',
            leadingIcon: Icons.code,
            child: SelectableText(
              _hasPrintableLabel ? _brailleOutput : '—',
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // --- Acción principal: crear la pieza imprimible ---
          AccessibleButton(
            label: 'Crear la etiqueta para imprimir',
            icon: Icons.print,
            pictogram: Icons.print,
            onPressed: _hasPrintableLabel ? _createPiece : null,
            hint: 'Genera el archivo STL de la etiqueta y lo abre en el visor',
          ),
          SizedBox(height: a11y.controlGap),
          AccessibleButton(
            label: 'Copiar Braille',
            icon: Icons.copy,
            pictogram: Icons.copy,
            isPrimary: false,
            onPressed: _hasPrintableLabel ? _copy : null,
            hint: 'Copia los caracteres Braille al portapapeles',
          ),
          SizedBox(height: a11y.controlGap),
          AccessibleButton(
            label: 'Compartir etiqueta',
            icon: Icons.share,
            pictogram: Icons.share,
            isPrimary: false,
            onPressed: _hasPrintableLabel ? _share : null,
            hint: 'Comparte el texto y su Braille con otra aplicación',
          ),
          SizedBox(height: a11y.controlGap),
          AccessibleButton(
            label: 'Ver todas las piezas',
            icon: Icons.threed_rotation,
            pictogram: Icons.threed_rotation,
            isPrimary: false,
            onPressed: () =>
                Navigator.of(context).push(GeneracionScreen.route()),
            hint: 'Abre la pantalla de generación de piezas',
          ),
          const SizedBox(height: AppSpacing.xl),
          LuminaInfoBanner(
            message:
                'La etiqueta se imprime con puntos de '
                '${LocalGeneratorService.brailleDotDiameter} mm de diámetro y '
                '${LocalGeneratorService.brailleDotHeight} mm de altura, con la '
                'separación estándar de ${LocalGeneratorService.brailleDotSpacing} mm, '
                'que son las medidas que la hacen legible con el dedo.',
            icon: Icons.print,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
