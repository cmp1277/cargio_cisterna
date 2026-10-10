import 'package:flutter/material.dart';

import 'theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 150});
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Image.asset(
      'assets/images/logo.png',
      width: width,
      fit: BoxFit.contain,
      semanticLabel: 'SCPE',
    ),
  );
}

class MessageBanner extends StatelessWidget {
  const MessageBanner({super.key, required this.message, this.success = false});
  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFE5F5EF) : const Color(0xFFFFF0EC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.info_outline,
            color: success ? const Color(0xFF176847) : const Color(0xFF9F341B),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4F4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        child,
      ],
    ),
  );
}

class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 540 ||
          MediaQuery.textScalerOf(context).scale(16) > 23) {
        return Column(children: [first, const SizedBox(height: 18), second]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 18),
          Expanded(child: second),
        ],
      );
    },
  );
}

class BusyIndicator extends StatelessWidget {
  const BusyIndicator({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
