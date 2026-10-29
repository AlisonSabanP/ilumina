import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_spacing.dart';
import '../../../shared/widgets/lumina_widgets.dart';
import '../../accesibilidad/providers/accessibility_provider.dart';
import '../providers/auth_provider.dart';
import 'orthosnap_screen.dart';
import '../../accesibilidad/widgets/accessibility_fab.dart';

/// Puerta de acceso al módulo clínico OrthoSnap.
///
/// La autenticación está **simulada** (no hay backend): el objetivo es
/// demostrar el control de acceso, la caducidad de sesión por inactividad y el
/// cierre que borra los datos del paciente de la memoria del dispositivo.
///
/// Las credenciales de demostración se muestran en pantalla de forma explícita
/// para que se pueda probar el módulo. En producción se sustituiría
/// [AuthProvider.login] por una llamada a un proveedor de identidad real.
class OrthoSnapLoginScreen extends StatefulWidget {
  const OrthoSnapLoginScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const OrthoSnapLoginScreen(),
      );

  @override
  State<OrthoSnapLoginScreen> createState() => _OrthoSnapLoginScreenState();
}

class _OrthoSnapLoginScreenState extends State<OrthoSnapLoginScreen> {
  final TextEditingController _idController =
      TextEditingController(text: AuthProvider.demoProfessionalId);
  final TextEditingController _passwordController =
      TextEditingController(text: AuthProvider.demoProfessionalPassword);
  final TextEditingController _nameController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    final ok = await auth.login(
      professionalId: _idController.text,
      password: _passwordController.text,
      displayName: _nameController.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      Navigator.of(context).pushReplacement(OrthoSnapScreen.route());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final a11y = AccessibilityProvider.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('OrthoSnap')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          LuminaPageHeader(
            title: 'Acceso profesional',
            subtitle:
                'OrthoSnap genera órtesis clínicas. Solo el personal sanitario '
                'autorizado puede entrar.',
            icon: Icons.medical_services_outlined,
            trailing: Icon(
              Icons.lock_outline,
              size: a11y.iconSize,
              color: theme.colorScheme.primary,
            ),
          ),

          const LuminaInfoBanner(
            message:
                'Módulo de demostración con acceso restringido simulado. No hay '
                'backend: la sesión se guarda solo en este dispositivo y caduca '
                'sola tras 30 minutos sin actividad.',
            icon: Icons.science_outlined,
          ),
          const SizedBox(height: AppSpacing.lg),

          LuminaSectionCard(
            title: 'Credenciales de la demo',
            subtitle: 'Se han rellenado automáticamente para que puedas entrar.',
            leadingIcon: Icons.vpn_key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _credentialRow(
                  context,
                  'N.º de colegiado',
                  AuthProvider.demoProfessionalId,
                ),
                _credentialRow(
                  context,
                  'Contraseña',
                  AuthProvider.demoProfessionalPassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          TextField(
            controller: _idController,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'N.º de colegiado',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                ),
                tooltip: _obscure ? 'Mostrar la contraseña' : 'Ocultar la contraseña',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre (opcional)',
              helperText: 'Aparecerá en el informe de la órtesis.',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),

          if (auth.error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            LuminaInfoBanner(
              message: auth.error!,
              icon: Icons.error_outline,
              tone: LuminaBannerTone.error,
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          AccessibleButton(
            label: 'Entrar',
            icon: Icons.login,
            pictogram: Icons.login,
            busy: _busy,
            onPressed: _busy ? null : _login,
            hint: 'Accede al módulo clínico OrthoSnap',
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _credentialRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: theme.textTheme.labelLarge),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
