import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';
import '../../formulario/modelos/formulario_modelos.dart';
import '../../generacion3d/pantallas/generacion_screen.dart';
import '../../generacion3d/providers/generation_provider.dart';
import '../../medicion/modelos/measurement_target.dart';
import '../../medicion/pantallas/medicion_hub_screen.dart';
import '../modelos/orthosnap_modelos.dart';
import '../providers/auth_provider.dart';
import 'orthosnap_login_screen.dart';

/// Formulario clínico de OrthoSnap.
///
/// Flujo del profesional:
///   1. Zona de la lesión y tipo de férula.
///   2. Indicación clínica y lado afectado.
///   3. Medidas del paciente (mano o manual).
///   4. Material y notas.
///   5. Generación con Meshy (estructura Voronoi, transpirable, alta precisión).
///
/// La sesión caduca por inactividad: si el profesional deja el dispositivo
/// abierto, al volver se le pedirá identificarse de nuevo y los datos del
/// paciente se habrán borrado de la memoria.
class OrthoSnapScreen extends StatefulWidget {
  const OrthoSnapScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const OrthoSnapScreen(),
      );

  @override
  State<OrthoSnapScreen> createState() => _OrthoSnapScreenState();
}

class _OrthoSnapScreenState extends State<OrthoSnapScreen> {
  final TextEditingController _diagnosisController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _generating = false;

  @override
  void initState() {
    super.initState();
    // Pre-rellena los campos con lo que ya hubiera en la sesión.
    final auth = context.read<AuthProvider>();
    _diagnosisController.text = auth.request.diagnosis;
    _notesController.text = auth.request.notes;
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final auth = context.read<AuthProvider>();
    final generation = context.read<GenerationProvider>();

    if (!auth.validateForGeneration()) return;

    setState(() => _generating = true);
    // Se prepara el envío antes de navegar, porque la pantalla de generación
    // lee el estado del provider, no la petición OrthoSnap.
    await generation.generateFromOrthoSnap(auth.request);
    if (!mounted) return;
    await Navigator.of(context).push(GeneracionScreen.route());
    if (!mounted) return;
    setState(() => _generating = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final a11y = AccessibilityProvider.of(context);

    // Caducidad de sesión: si expiró, se vuelve al login.
    if (!auth.isAuthenticated || auth.isSessionExpired) {
      return Scaffold(
        appBar: AppBar(title: const Text('OrthoSnap')),
        body: LuminaErrorView(
          title: auth.isSessionExpired
              ? 'La sesión ha caducado'
              : 'Sesión no iniciada',
          message: auth.isSessionExpired
              ? 'Por seguridad, la sesión clínica caduca tras 30 minutos sin '
                  'actividad y los datos del paciente se borran.'
              : 'Necesitas identificarte para acceder al módulo clínico.',
          retryLabel: 'Identificarme',
          onRetry: () {
            auth.logout();
            Navigator.of(context).pushReplacement(
              OrthoSnapLoginScreen.route(),
            );
          },
        ),
      );
    }

    final request = auth.request;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OrthoSnap'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Text(
                '${auth.minutesLeft} min',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar la sesión y borrar los datos del paciente',
            onPressed: () {
              auth.logout();
              Navigator.of(context).pushReplacement(
                OrthoSnapLoginScreen.route(),
              );
            },
          ),
        ],
      ),
      floatingActionButton: const AccessibilityFab(heroTag: 'ortho.a11y'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          LuminaPageHeader(
            title: 'Ficha clínica',
            subtitle:
                'Sesión de ${auth.professionalName ?? 'profesional'} · '
                'colegiado ${auth.professionalId ?? '—'}',
            icon: Icons.medical_services_outlined,
          ),

          // Aviso legal: siempre visible.
          const LuminaInfoBanner(
            message: OrthoSnapRequest.disclaimer,
            icon: Icons.gavel,
            tone: LuminaBannerTone.error,
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Zona ---
          LuminaSectionCard(
            title: 'Zona de la lesión',
            leadingIcon: Icons.accessibility_new,
            child: Column(
              children: [
                for (var i = 0; i < BodyZone.values.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: PictogramOptionTile(
                      label: BodyZone.values[i].label,
                      icon: BodyZone.values[i].icon,
                      pictogram: BodyZone.values[i].icon,
                      selected: request.bodyZone == BodyZone.values[i],
                      onTap: () => auth.setBodyZone(BodyZone.values[i]),
                      semanticKey: OrdinalSortKey(i.toDouble()),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Tipo de férula ---
          LuminaSectionCard(
            title: 'Tipo de férula',
            leadingIcon: Icons.healing,
            child: Column(
              children: [
                for (var i = 0; i < SplintType.values.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: PictogramOptionTile(
                      label: SplintType.values[i].label,
                      description: SplintType.values[i].description,
                      icon: SplintType.values[i].icon,
                      pictogram: SplintType.values[i].icon,
                      selected: request.splintType == SplintType.values[i],
                      onTap: () => auth.setSplintType(SplintType.values[i]),
                      semanticKey: OrdinalSortKey(i.toDouble()),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Datos clínicos ---
          LuminaSectionCard(
            title: 'Indicación clínica',
            subtitle: 'Obligatoria. Describe para qué se prescribe la órtesis.',
            leadingIcon: Icons.description_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _diagnosisController,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Diagnóstico o indicación',
                    helperText:
                        'Por ejemplo: tendinitis del túnel carpiano, '
                        'inmovilización nocturna en extensión neutra.',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                  onChanged: auth.setDiagnosis,
                ),
                SizedBox(height: a11y.controlGap),
                Semantics(
                  label: 'Lado afectado',
                  child: SegmentedButton<String>(
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(
                        value: 'izquierda',
                        label: Text('Izquierda'),
                        icon: Icon(Icons.west),
                      ),
                      ButtonSegment(
                        value: 'derecha',
                        label: Text('Derecha'),
                        icon: Icon(Icons.east),
                      ),
                    ],
                    selected: request.affectedSide == null
                        ? const <String>{}
                        : {request.affectedSide!},
                    onSelectionChanged: (selection) => auth.setAffectedSide(
                      selection.isEmpty ? null : selection.first,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Medidas ---
          LuminaSectionCard(
            title: 'Medidas del paciente',
            subtitle: request.measurements.isEmpty
                ? 'Se exige al menos una medida para generar la órtesis.'
                : '${request.measurements.length} medida(s) registradas.',
            leadingIcon: Icons.straighten,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (request.measurements.isEmpty)
                  Text(
                    'Recomendadas: ${request.suggestedMeasurements.join(', ')}.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  for (final measurement in request.measurements)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.straighten),
                      title: Text(measurement.label),
                      subtitle: Text(measurement.source.label),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            measurement.display,
                            style: theme.textTheme.titleMedium,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Eliminar ${measurement.label}',
                            onPressed: () =>
                                auth.removeMeasurement(measurement.id),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: AppSpacing.md),
                AccessibleButton(
                  label: 'Medir al paciente',
                  icon: Icons.straighten,
                  pictogram: Icons.straighten,
                  isPrimary: false,
                  onPressed: () => Navigator.of(context).push(
                    MedicionHubScreen.route(
                      target: MeasurementTarget.clinico,
                    ),
                  ),
                  hint: 'Abre la medición de mano o la medida a mano',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // --- Material y notas ---
          LuminaSectionCard(
            title: 'Material y notas',
            leadingIcon: Icons.layers,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Material', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final material in MaterialQuestion.options)
                      ChoiceChip(
                        label: Text(material),
                        selected: request.material == material,
                        onSelected: (_) => auth.setMaterial(material),
                      ),
                  ],
                ),
                SizedBox(height: a11y.controlGap),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas profesionales',
                    helperText:
                        'Detalles de ajuste, materiales o cuidados del paciente.',
                    prefixIcon: Icon(Icons.notes),
                  ),
                  onChanged: auth.setNotes,
                ),
              ],
            ),
          ),

          // --- Error de validación ---
          if (auth.validationError != null) ...[
            const SizedBox(height: AppSpacing.lg),
            LuminaInfoBanner(
              message: auth.validationError!,
              icon: Icons.error_outline,
              tone: LuminaBannerTone.error,
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // --- Resumen ---
          LuminaSectionCard(
            title: 'Resumen de la órtesis',
            subtitle: request.title,
            leadingIcon: Icons.summarize,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(theme, 'Zona', request.bodyZone.label),
                _summaryRow(theme, 'Tipo', request.splintType.label),
                _summaryRow(
                  theme,
                  'Lado',
                  request.affectedSide ?? 'no especificado',
                ),
                _summaryRow(
                  theme,
                  'Medidas',
                  '${request.measurements.length}',
                ),
                _summaryRow(theme, 'Material', request.material),
                const SizedBox(height: AppSpacing.lg),

                AccessibleButton(
                  label: 'Generar órtesis',
                  icon: Icons.auto_awesome,
                  pictogram: Icons.auto_awesome,
                  busy: _generating,
                  onPressed: _generating ? null : _generate,
                  hint: 'Genera la órtesis a partir de la ficha clínica',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _summaryRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: theme.textTheme.labelLarge),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
