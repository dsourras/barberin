part of 'main.dart';

class AuthTopBar extends StatelessWidget {
  const AuthTopBar({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
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
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF242424)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: Color(0xFFD1A45C),
              ),
            ),
          ),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF0D0D0D),
        border: Border.all(color: const Color(0xFF3B2D1C)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset(
          'assets/images/barbero_app_icon.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF262626)),
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
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1713),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF3E3224)),
          ),
          child: Icon(icon, color: const Color(0xFFD1A45C), size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF5ECDD),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8F8F8F)),
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
  });

  final String label;
  final String value;
  final IconData icon;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            color: Color(0xFFC6A56E),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0E0E0E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF8A6A3C)),
              const SizedBox(width: 10),
              Expanded(
                child: controller == null
                    ? Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFF0E5D1),
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : TextField(
                        controller: controller,
                        keyboardType: keyboardType,
                        obscureText: obscureText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFF0E5D1),
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                        ),
                        cursorColor: Color(0xFFD1A45C),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: Color(0xFFD1A45C),
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
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD1A45C),
          foregroundColor: const Color(0xFF0B0B0B),
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
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF3A3127)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF0E5D1),
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
    const items = [
      (Icons.home_outlined, '\u0391\u03c1\u03c7\u03b9\u03ba\u03ae'),
      (
        Icons.calendar_today_outlined,
        '\u03a0\u03c1\u03cc\u03b3\u03c1\u03b1\u03bc\u03bc\u03b1',
      ),
      (
        Icons.person_outline_rounded,
        '\u03a0\u03b5\u03bb\u03ac\u03c4\u03b5\u03c2',
      ),
      (
        Icons.bar_chart_outlined,
        '\u0391\u03bd\u03b1\u03c6\u03bf\u03c1\u03ad\u03c2',
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF242424)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (index) {
          final item = items[index];
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onTap(index),
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: NavItem(
                      icon: item.$1,
                      label: item.$2,
                      active: currentIndex == index,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFD1A45C) : const Color(0xFF7C7C7C);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
