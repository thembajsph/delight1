import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';

class _Slide {
  final String emoji, title, subtitle;
  final List<Color> gradient;
  const _Slide({required this.emoji, required this.title,
    required this.subtitle, required this.gradient});
}

const _slides = [
  _Slide(
    emoji: '💸',
    title: 'Send money instantly',
    subtitle: 'Send money to anyone in seconds. '
      'Cheaper than the bank. No hidden fees. Works on any phone.',
    gradient: [Color(0xFF00C96A), Color(0xFF004D28)]),
  _Slide(
    emoji: '🎟',
    title: 'Your ticket. Your memory.',
    subtitle: 'Buy a ticket, keep it forever. '
      'Show it at the door. Share it with friends. '
      'It\'s yours — no one can take it away.',
    gradient: [Color(0xFFD4AF37), Color(0xFF6B5000)]),
  _Slide(
    emoji: '🏪',
    title: 'Add money anywhere',
    subtitle: 'No bank account needed. '
      'Add money at your nearest spaza shop, garage or tuck shop. '
      'Cash works. Always.',
    gradient: [Color(0xFF4A9EFF), Color(0xFF003D8F)]),
  _Slide(
    emoji: '🔥',
    title: 'Events near you',
    subtitle: 'See what\'s happening in your city. '
      'Buy tickets in one tap. '
      'Share your experience with everyone.',
    gradient: [Color(0xFFE8463A), Color(0xFF7A0E09)]),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _current = 0;
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _next() {
    if (_current < _slides.length - 1) {
      _ctrl.reset();
      setState(() => _current++);
      _ctrl.forward();
    } else {
      ref.read(isOnboardedProvider.notifier).state = true;
      context.go('/signup');
    }
  }

  void _skip() {
    ref.read(isOnboardedProvider.notifier).state = true;
    context.go('/signup');
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_current];
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        width: double.infinity, height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: slide.gradient,
            begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text('Skip', style: TextStyle(
                  fontFamily: 'Satoshi',
                  color: Colors.white.withOpacity(0.7), fontSize: 15)))),
            const Spacer(),
            FadeTransition(opacity: _fade,
              child: Text(slide.emoji,
                style: const TextStyle(fontSize: 88))),
            const SizedBox(height: 32),
            FadeTransition(opacity: _fade,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(slide.title, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Clash', fontSize: 36,
                    fontWeight: FontWeight.w700, color: Colors.white,
                    height: 1.1, letterSpacing: -0.8)))),
            const SizedBox(height: 16),
            FadeTransition(opacity: _fade,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(slide.subtitle, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 16,
                    color: Colors.white.withOpacity(0.82), height: 1.6)))),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _current;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 28 : 8, height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: active ? Colors.white : Colors.white.withOpacity(0.3)));
              })),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: _next,
                child: Container(
                  height: 60, width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.35))),
                  alignment: Alignment.center,
                  child: Text(
                    _current == _slides.length - 1 ? 'Get Started →' : 'Next →',
                    style: const TextStyle(fontFamily: 'Satoshi',
                      color: Colors.white, fontSize: 17,
                      fontWeight: FontWeight.w700))))),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}
