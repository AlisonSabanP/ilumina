import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../modelos/measurement_models.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';

/// Entrada manual de una medida.
///
/// Es la red de seguridad de todo el módulo de medición: si el dispositivo no
/// tiene AR, si el usuario prefiere una regla o si un profesional quiere
/// introducir una medida clínica, este formulario siempre está disponible.
class ManualMeasurementScreen extends StatefulWidget {
  const ManualMeasurementScreen({
    super.key,
    this.defaultLabel = '',
    this.suggestedLabels = const <String>[],
  });

  final String defaultLabel;

  /// Etiquetas sugeridas para agilizar la entrada (se muestran como chips).
  final List<String> suggestedLabels;

  static Route<void> route({
    String defaultLabel = '',
    List<String> suggestedLabels = const <String>[],
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => ManualMeasurementScreen(
          defaultLabel: defaultLabel,
          suggestedLabels: suggestedLabels,
        ),
      );

  @override
  State<ManualMeasurementScreen> createState() =>
      _ManualMeasurementScreenState();
}

class _ManualMeasurementScreenState extends State<ManualMeasurementScreen> {
  late final TextEditingController _labelController =
      TextEditingController(text: widget.defaultLabel);
  final TextEditingController _valueController = TextEditingController();

  MeasurementKind _kind = MeasurementKind.manualDiameter;

  /// Unidad en la que escribe el usuario; internamente todo es centímetros.
  _Unit _unit = _Unit.centimeters;

  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  double? get _valueCm {
    final raw = _valueController.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;
    return switch (_unit) {
      _Unit.millimeters => value / 10,
      _Unit.centimeters => value,
      _Unit.meters => value * 100,
    };
  }

  void _save() {
    final label = _labelController.text.trim();
    final valueCm = _valueCm;

    if (label.isEmpty) {
      setState(() => _error = 'Escribe qué has medido.');
      return;
    }
    if (valueCm == null) {
      setState(() => _error = 'Escribe un número mayor que cero.');
      return;
    }
    // Se descartan valores absurdos para evitar prompts sin sentido.
    if (valueCm > 500) {
      setState(() => _error =
          'Esa medida parece demasiado grande (${valueCm.toStringAsFixed(0)} cm). '
          'Comprueba la unidad.');
      return;
    }

    context.read<FormularioProvider>().upsertMeasurement(
          Measurement(
            id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
            label: label,
            valueCm: valueCm,
            kind: _kind,
            source: MeasurementSource.manual,
            timestamp: DateTime.now(),
          ),
        );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final a11y = AccessibilityProvider.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Medida a mano')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const LuminaPageHeader(
            title: 'Medida a mano',
            subtitle:
                'Escribe la medida con una regla. Es la forma más fiable si no hay AR disponible.',
            icon: Icons.straighten,
          ),

          if (widget.suggestedLabels.isNotEmpty) ...[
            LuminaSectionCard(
              title: 'Medidas recomendadas',
              subtitle: 'Toca una para usarla como nombre.',
              leadingIcon: Icons.lightbulb_outline,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final suggestion in widget.suggestedLabels)
                    ActionChip(
                      label: Text(suggestion),
                      onPressed: () {
                        _labelController.text = suggestion;
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '¿Qué has medido?',
              helperText: 'Por ejemplo: perímetro de muñeca',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          LuminaSectionCard(
            title: 'Valor',
            leadingIcon: Icons.numbers,
            child: Column(
              children: [
                TextField(
                  controller: _valueController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Cantidad',
                    suffixText: _unit.label,
                    prefixIcon: const Icon(Icons.straighten),
                    errorText: _error,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                SizedBox(height: a11y.controlGap),
                Semantics(
                  label: 'Unidad de la medida',
                  child: SegmentedButton<_Unit>(
                    segments: const [
                      ButtonSegment(
                        value: _Unit.millimeters,
                        label: Text('mm'),
                      ),
                      ButtonSegment(
                        value: _Unit.centimeters,
                        label: Text('cm'),
                      ),
                      ButtonSegment(value: _Unit.meters, label: Text('m')),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (selection) =>
                        setState(() => _unit = selection.first),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          LuminaSectionCard(
            title: 'Tipo de medida',
            subtitle: 'Ayuda a Lumina a colocarla en el prompt del modelo.',
            leadingIcon: Icons.category_outlined,
            child: Column(
              children: [
                RadioGroup<MeasurementKind>(
                  groupValue: _kind,
                  onChanged: (value) {
                    if (value != null) setState(() => _kind = value);
                  },
                  child: Column(
                    children: [
                      for (final kind in MeasurementKind.values)
                        RadioListTile<MeasurementKind>(
                          value: kind,
                          title: Text(kind.label),
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          AccessibleButton(
            label: 'Guardar medida',
            icon: Icons.check,
            pictogram: Icons.check,
            onPressed: _save,
            hint: 'Añade la medida al formulario',
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

enum _Unit {
  millimeters('mm'),
  centimeters('cm'),
  meters('m');

  const _Unit(this.label);

  final String label;
}
