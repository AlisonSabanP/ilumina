import 'package:flutter/foundation.dart';

import '../../../shared/servicios/braille_service.dart';
import '../../formulario/modelos/formulario_modelos.dart';
import '../../formulario/modelos/formulario_provider.dart';
import '../../medicion/modelos/measurement_models.dart';
import '../../progrip/modelos/progrip_modelos.dart';
import '../../orthosnap/modelos/orthosnap_modelos.dart';

/// Servicio que traduce el estado de la app a un prompt enriquecido para Meshy.
///
/// El prompt se compone por capas, siempre en el mismo orden, para que el
/// resultado sea reproducible y fácil de depurar:
///
///   1. Objeto principal (semilla de la recomendación, módulo ProGrip u
///      OrthoSnap).
///   2. Contexto de la persona (perfil y respuestas del formulario).
///   3. Medidas reales capturadas (AR, mano o manuales).
///   4. Material y acabado.
///   5. Requisitos de impresión y de accesibilidad.
///
/// Meshy limita el prompt a 800 caracteres: [buildPrompt] recorta de forma
/// segura en el último punto y avisa con [PromptBuildResult.wasTrimmed].
class PromptBuilderService {
  const PromptBuilderService();

  /// Límite documentado por Meshy para `prompt`.
  static const int maxPromptLength = 800;

  /// Prompt para el flujo general (formulario + medidas).
  PromptBuildResult fromFormulario(FormularioProvider form) {
    final recommendation = form.recommendation;
    if (recommendation == null) {
      throw StateError(
        'El formulario no tiene recomendación: no se puede construir el prompt.',
      );
    }

    final parts = <String>[
      recommendation.promptSeed,
      _profileContext(form.profile),
      ...form.promptFragments,
      _measurementsBlock(form.measurements),
      _brailleBlock(form.brailleLabel),
      _materialBlock(form.material),
      _printingBlock(),
      _accessibilityBlock(form.profile),
    ];

    return _assemble(parts, seed: recommendation.promptSeed);
  }

  /// Prompt para el módulo ProGrip (base + garfio + adaptador).
  PromptBuildResult fromProGrip(ProGripConfig config) {
    final parts = <String>[
      'Custom 3D printable assistive tool grip for a person with limited hand strength',
      'Three-part design printed as one piece: a mounting base, a functional hook and a tool adapter',
      'Base: ${config.base.label} (${config.base.description})',
      'Hook: ${config.hook.label} (${config.hook.description})',
      'Tool adapter: ${config.adapter.label} for a ${config.adapter.toolName}',
      ...config.hook.promptFragments,
      ...config.adapter.promptFragments,
      if (config.handMeasurements.isNotEmpty)
        _measurementsBlock(config.handMeasurements),
      if (config.notes.trim().isNotEmpty) 'Additional requirement: ${config.notes.trim()}',
      _materialBlock(config.material),
      _printingBlock(),
      'All edges must be rounded, the surface smooth on the palm side and textured where the fingers rest',
      'Include a safety strap hole so the tool cannot be dropped',
      _brailleBlock('progrip ${config.adapter.label}'),
    ];

    return _assemble(parts, seed: 'ProGrip assistive tool grip');
  }

  /// Prompt para el módulo OrthoSnap (órtesis clínica).
  PromptBuildResult fromOrthoSnap(OrthoSnapRequest request) {
    final parts = <String>[
      'Custom 3D printable ${request.splintType.label.toLowerCase()} for the ${request.bodyZone.label.toLowerCase()}',
      'Clinical orthosis designed by a health professional for a real patient',
      'Voronoi structure to reduce weight while keeping mechanical strength',
      'Breathable open-cell lattice so the skin stays dry',
      'High precision fit, smooth inner surface with no pressure points',
      'Semi-rigid material that supports the joint but allows controlled movement',
      if (request.diagnosis.trim().isNotEmpty)
        'Clinical indication: ${request.diagnosis.trim()}',
      if (request.affectedSide != null) 'Affected side: ${request.affectedSide}',
      if (request.notes.trim().isNotEmpty) 'Professional notes: ${request.notes.trim()}',
      if (request.measurements.isNotEmpty)
        _measurementsBlock(request.measurements),
      _materialBlock(request.material),
      _printingBlock(),
      'Include ventilation openings of at least 4 mm and rounded borders for skin comfort',
    ];

    return _assemble(parts, seed: 'OrthoSnap clinical orthosis');
  }

  // --- Bloques ---------------------------------------------------------------

  String _profileContext(NeedProfile? profile) => switch (profile) {
        NeedProfile.motriz =>
          'The user has a motor disability with limited grip strength and reduced hand mobility',
        NeedProfile.visual =>
          'The user is blind or has very low vision and identifies objects by touch',
        NeedProfile.cognitiva =>
          'The user is autistic or has sensory sensitivity: the object must be predictable, quiet and pleasant to touch',
        null => 'The user needs an accessible 3D printed object',
      };

  String _measurementsBlock(List<Measurement> measurements) {
    if (measurements.isEmpty) {
      return 'No exact measurements available: use standard ergonomic proportions for an adult hand';
    }
    final phrases = measurements.map((m) => m.promptPhrase).join('. ');
    return 'Real measurements of the user: $phrases';
  }

  /// Bloque que pide grabar la etiqueta Braille en la propia pieza.
  ///
  /// Meshy trabaja con texto en inglés y no puede generar puntos Braille a
  /// partir de los caracteres Unicode, así que la instrucción es geométrica:
  /// relieve de 1,5 mm de alto y 2,5 mm entre puntos, que son las medidas que
  /// hacen legible una etiqueta impresa con el dedo.
  String _brailleBlock(String? label) {
    final text = label == null ? '' : BrailleService.prepareLabel(label);
    if (text.isEmpty) return '';
    return 'Emboss a Braille label directly on the surface of the part, '
        'reading "$text", with raised dots 1.5 mm high and 2.5 mm apart, '
        'in a recessed flat area so the dots are not worn down in use';
  }

  String _materialBlock(String material) {
    final hint = MaterialQuestion.promptHints[material] ??
        'Smooth durable surface suitable for daily use';
    return 'Print material: $material. $hint';
  }

  String _printingBlock() =>
      'Must be printable without supports on a standard FDM printer, minimum wall thickness 2 mm, '
      'no sharp edges, all corners filleted';

  String _accessibilityBlock(NeedProfile? profile) => switch (profile) {
        NeedProfile.motriz =>
          'Easy one-hand grip, wide contact surfaces, no fine pinch required',
        NeedProfile.visual =>
          'Add tactile orientation features so the object can be recognised by touch alone',
        NeedProfile.cognitiva =>
          'Simple recognisable shape, no small loose parts, no sudden changes in texture',
        null => 'Design for accessibility and comfort',
      };

  // --- Ensamblado ------------------------------------------------------------

  /// Une los bloques y recorta a [maxPromptLength] de forma segura.
  PromptBuildResult _assemble(List<String> parts, {required String seed}) {
    final cleaned = parts
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);

    final full = cleaned.join('. ').replaceAll(RegExp(r'\.\.+'), '.');
    final normalized = full.endsWith('.') ? full : '$full.';

    if (normalized.length <= maxPromptLength) {
      return PromptBuildResult(
        prompt: normalized,
        seed: seed,
        wasTrimmed: false,
        originalLength: normalized.length,
      );
    }

    // Recorte seguro: se corta en el último punto antes del límite para no
    // dejar una frase a medias (Meshy interpreta mejor frases completas).
    final cut = normalized.substring(0, maxPromptLength - 1);
    final lastPeriod = cut.lastIndexOf('. ');
    final trimmed = lastPeriod > maxPromptLength ~/ 2
        ? cut.substring(0, lastPeriod + 1)
        : cut;

    return PromptBuildResult(
      prompt: trimmed,
      seed: seed,
      wasTrimmed: true,
      originalLength: normalized.length,
    );
  }
}

/// Resultado de construir un prompt, con aviso de recorte.
@immutable
class PromptBuildResult {
  const PromptBuildResult({
    required this.prompt,
    required this.seed,
    required this.wasTrimmed,
    required this.originalLength,
  });

  final String prompt;

  /// Frase semilla (sirve de título corto en la UI).
  final String seed;

  /// `true` si hubo que recortar porque el prompt superaba 800 caracteres.
  final bool wasTrimmed;

  /// Longitud antes del recorte.
  final int originalLength;

  int get length => prompt.length;

  @override
  String toString() => 'PromptBuildResult($length chars, trimmed: $wasTrimmed)';
}
