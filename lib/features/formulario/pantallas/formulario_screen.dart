import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../features/accesibilidad/widgets/accessibility_fab.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../generacion3d/pantallas/generacion_screen.dart';
import '../../medicion/pantallas/medicion_hub_screen.dart';
import '../modelos/formulario_modelos.dart';
import '../modelos/formulario_provider.dart';
import 'braille_screen.dart';

/// Formulario inteligente ramificado.
///
/// Flujo:
///   1. Elección de perfil (motriz / visual / cognitiva).
///   2. Preguntas ramificadas: cada respuesta decide la siguiente pregunta.
///   3. Revisión: recomendación, medidas capturadas y etiqueta Braille
///      opcional (pieza aparte).
///
/// Todas las opciones se presentan con [PictogramOptionTile], que respeta los
/// modos de botones grandes y pictogramas.
class FormularioScreen extends StatelessWidget {
  const FormularioScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const FormularioScreen(),
      );

  @override
  Widget build(BuildContext context) {
    final form = context.watch<FormularioProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Formulario inteligente'),
        leading: form.needsProfile
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver a la pregunta anterior',
                onPressed: form.goBack,
              ),
        actions: [
          if (!form.needsProfile)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Empezar el formulario de nuevo',
              onPressed: form.reset,
            ),
          const AccessibilityAppBarAction(),
        ],
      ),
      floatingActionButton: const AccessibilityFab(heroTag: 'form.a11y'),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _buildBody(context, form),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FormularioProvider form) {
    if (form.needsProfile) {
      return _ProfileStep(key: const ValueKey('profile'));
    }
    final question = form.currentQuestion;
    if (question != null) {
      return _QuestionStep(
        key: ValueKey('q_${question.id}'),
        question: question,
      );
    }
    return const _ReviewStep(key: ValueKey('review'));
  }
}

/// Paso 1: elección del perfil de necesidad.
class _ProfileStep extends StatelessWidget {
  const _ProfileStep({super.key});

  @override
  Widget build(BuildContext context) {
    final form = context.read<FormularioProvider>();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const LuminaPageHeader(
          title: '¿Qué necesitas?',
          subtitle:
              'Elige el punto de partida. Después te haremos unas preguntas breves para ajustar el diseño.',
          icon: Icons.assignment_ind,
        ),
        for (final profile in NeedProfile.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: PictogramOptionTile(
              label: profile.label,
              description: profile.description,
              icon: profile.pictogram,
              pictogram: profile.pictogram,
              selected: false,
              onTap: () => form.selectProfile(profile),
              semanticKey: OrdinalSortKey(profile.index.toDouble()),
            ),
          ),
      ],
    );
  }
}

/// Paso 2: una pregunta del árbol.
class _QuestionStep extends StatelessWidget {
  const _QuestionStep({super.key, required this.question});

  final FormQuestion question;

  @override
  Widget build(BuildContext context) {
    final form = context.read<FormularioProvider>();
    final current = context.select<FormularioProvider, String?>(
      (f) => f.answerLabel(question.id),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        LuminaPageHeader(
          title: question.prompt,
          subtitle: question.helper,
          icon: question.pictogram,
        ),
        for (var i = 0; i < question.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: PictogramOptionTile(
              label: question.options[i].label,
              description: question.options[i].description,
              icon: question.options[i].pictogram ?? Icons.check,
              pictogram: question.options[i].pictogram,
              selected: current == question.options[i].label,
              onTap: () => form.answer(question.options[i].id),
              semanticKey: OrdinalSortKey(i.toDouble()),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        const LuminaInfoBanner(
          message:
              'Puedes volver atrás con la flecha de arriba: no perderás las respuestas que ya diste.',
          icon: Icons.undo,
        ),
      ],
    );
  }
}

/// Paso 3: revisión, medidas y etiqueta Braille opcional.
class _ReviewStep extends StatelessWidget {
  const _ReviewStep({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final form = context.watch<FormularioProvider>();
    final recommendation = form.recommendation;

    if (recommendation == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'El formulario quedó incompleto.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              AccessibleButton(
                label: 'Empezar de nuevo',
                icon: Icons.restart_alt,
                onPressed: form.reset,
                expand: false,
              ),
            ],
          ),
        ),
      );
    }

    final missing = form.missingSuggestedMeasurements;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const LuminaPageHeader(
          title: 'Tu recomendación',
          subtitle: 'Revisa los datos antes de generar el modelo 3D.',
          icon: Icons.verified,
        ),

        // --- Recomendación ---
        LuminaSectionCard(
          title: recommendation.title,
          subtitle: recommendation.description,
          leadingIcon: recommendation.icon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resumen de tus respuestas', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(form.summary, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Medidas ---
        LuminaSectionCard(
          title: 'Medidas capturadas',
          subtitle: form.measurements.isEmpty
              ? 'Aún no hay medidas. Puedes continuar y ajustar el tamaño después.'
              : '${form.measurements.length} medida(s) disponibles.',
          leadingIcon: Icons.straighten,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (form.measurements.isEmpty)
                Text(
                  'Sin medidas. Un modelo sin medidas usa proporciones estándar.',
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final measurement in form.measurements)
                  Semantics(
                    label:
                        '${measurement.label}: ${measurement.display}, origen ${measurement.source.label}',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_sourceIcon(measurement.source)),
                      title: Text(measurement.label),
                      subtitle: Text(measurement.source.label),
                      trailing: Text(
                        measurement.display,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                LuminaInfoBanner(
                  message:
                      'Medidas recomendadas para esta pieza que aún faltan: ${missing.join(', ')}.',
                  icon: Icons.info_outline,
                  tone: LuminaBannerTone.warning,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              AccessibleButton(
                label: form.measurements.isEmpty
                    ? 'Medir con la cámara'
                    : 'Añadir o revisar medidas',
                icon: Icons.straighten,
                pictogram: Icons.straighten,
                isPrimary: false,
                onPressed: () =>
                    Navigator.of(context).push(MedicionHubScreen.route()),
                hint: 'Abre la medición con cámara o con regla',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // --- Etiqueta en Braille (pieza aparte, opcional) ---
        //
        // La etiqueta nunca se graba sobre la pieza: es una pieza
        // independiente que se crea solo si el usuario la pide.
        LuminaSectionCard(
          title: 'Etiqueta en Braille (opcional)',
          subtitle: form.hasCustomBrailleLabel
              ? 'Tu etiqueta: "${form.brailleLabel}"'
              : 'Una pieza aparte para imprimir y pegar. Nunca se añade a la '
                  'pieza principal.',
          leadingIcon: Icons.dialpad,
          child: AccessibleButton(
            label: form.hasCustomBrailleLabel
                ? 'Editar etiqueta en Braille'
                : 'Crear etiqueta en Braille',
            icon: Icons.dialpad,
            pictogram: Icons.dialpad,
            isPrimary: false,
            onPressed: () => Navigator.of(context).push(BrailleScreen.route()),
            hint: 'Escribe el texto, míralo en Braille y créalo como pieza aparte',
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // --- Generar ---
        AccessibleButton(
          label: 'Generar modelo 3D',
          icon: Icons.auto_awesome,
          pictogram: Icons.auto_awesome,
          hint: 'Genera el modelo y muestra el progreso',
          onPressed: () =>
              Navigator.of(context).push(GeneracionScreen.route()),
        ),
        const SizedBox(height: AppSpacing.md),
        AccessibleButton(
          label: 'Empezar de nuevo',
          icon: Icons.restart_alt,
          pictogram: Icons.restart_alt,
          isPrimary: false,
          onPressed: form.reset,
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  IconData _sourceIcon(dynamic source) {
    final name = source.toString();
    if (name.contains('hand')) return Icons.back_hand;
    return Icons.edit;
  }
}
