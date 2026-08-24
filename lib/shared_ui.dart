part of 'main.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, required this.width, this.height});

  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      height: height ?? width / 3.2,
      child: Container(
        padding: isDark
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : EdgeInsets.zero,
        decoration: isDark
            ? BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Image.asset(
          'assets/images/barberin_wordmark_modern.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class AuthTopBar extends StatelessWidget {
  const AuthTopBar({super.key, required this.onBack, this.logoTopPadding = 0});

  final VoidCallback onBack;
  final double logoTopPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onBack,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: scheme.primary,
              ),
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.only(top: logoTopPadding),
          child: const BrandWordmark(width: 132),
        ),
      ],
    );
  }
}

class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.symmetric(horizontal: size * .08),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: scheme.surface,
        border: Border.all(color: scheme.outline),
      ),
      child: Center(child: BrandWordmark(width: size * .84)),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline),
          ),
          child: Icon(icon, color: scheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.icon,
    this.value = '',
    this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.large = false,
    this.fieldHeight,
  });

  final String label;
  final String value;
  final IconData icon;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool large;
  final double? fieldHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final largeFieldHeight = fieldHeight ?? 64;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: large ? 12 : 11,
            letterSpacing: large ? 0.5 : 0.8,
            color: scheme.primary,
          ),
        ),
        SizedBox(height: large ? 6 : 8),
        if (large)
          SizedBox(
            height: largeFieldHeight,
            child: controller == null
                ? InputDecorator(
                    decoration: _appTextFieldDecoration(
                      scheme: scheme,
                      icon: icon,
                      fieldHeight: largeFieldHeight,
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    obscureText: obscureText,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: _appTextFieldDecoration(
                      scheme: scheme,
                      icon: icon,
                      fieldHeight: largeFieldHeight,
                    ),
                    cursorColor: scheme.primary,
                  ),
          )
        else
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.barberinBorder)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: controller == null
                      ? Text(
                          value,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : TextField(
                          controller: controller,
                          keyboardType: keyboardType,
                          obscureText: obscureText,
                          textAlignVertical: TextAlignVertical.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                          ),
                          cursorColor: scheme.primary,
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

InputDecoration _appTextFieldDecoration({
  required ColorScheme scheme,
  required IconData icon,
  required double fieldHeight,
}) {
  return InputDecoration(
    filled: false,
    prefixIcon: Icon(icon, size: 20, color: scheme.primary),
    prefixIconConstraints: BoxConstraints(minWidth: 52, minHeight: fieldHeight),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    border: UnderlineInputBorder(borderSide: BorderSide(color: scheme.outline)),
    enabledBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: scheme.outline),
    ),
    focusedBorder: UnderlineInputBorder(
      borderSide: BorderSide(color: scheme.primary, width: 1.4),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: scheme.primary,
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class ManualAppointmentAction extends StatelessWidget {
  const ManualAppointmentAction({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.32)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: scheme.primary, size: 16),
              const SizedBox(width: 5),
              Text(
                'Νέο ραντεβού',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = [
      'Επισκόπηση',
      'Πρόγραμμα',
      'Πελάτες',
      'Αναφορές',
      'Περισσότερα',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(labels.length, (index) {
            final active = index == currentIndex;
            return Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onTap(index),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        labels[index],
                        style: TextStyle(
                          color: active
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: active
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
