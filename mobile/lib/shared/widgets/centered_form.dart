import 'package:material_ui/material_ui.dart';

/// Centered single-column layout for the Create/Join screens.
class CenteredForm extends StatelessWidget {
  const CenteredForm({super.key, required this.children, this.onBack, this.trailing});

  final List<Widget> children;
  final VoidCallback? onBack;

  /// Optional top-right action (e.g. settings).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
            if (trailing != null) Positioned(right: 4, top: 4, child: trailing!),
            if (onBack != null)
              Positioned(
                left: 4,
                top: 4,
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
