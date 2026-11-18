import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/models/models.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  UserRole _selectedRole = UserRole.consumer;

  Future<void> _login() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty)    { _snack('Please enter your email'); return; }
    if (!email.contains('@')) { _snack('Enter a valid email address'); return; }
    if (password.isEmpty) { _snack('Please enter your password'); return; }

    setState(() => _loading = true);
    try {
      await SupabaseService.signIn(email: email, password: password);
      // AuthNotifier.onAuthStateChange fires automatically and sets the user
      if (mounted) context.go('/feed');
    } catch (e) {
      final raw = e.toString().replaceAll('Exception: ','').replaceAll('AuthException: ','');
      final msg = raw.toLowerCase().contains('invalid login credentials') ||
                  raw.toLowerCase().contains('invalid')
        ? 'Wrong email or password. Try again.'
        : raw.toLowerCase().contains('email not confirmed')
          ? 'Please confirm your email first. Check your inbox.'
          : raw;
      if (mounted) _snack(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _loading = true);
    try {
      // On web: use OAuth redirect (no google_sign_in package needed)
      // On Android/iOS: signInWithGoogle() uses the native SDK
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.toString(),
      );
      // The redirect will reload the page and Supabase will pick up the session
      // authProvider listener handles state automatically
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        if (msg.contains('provider is not enabled') || msg.contains('validation_failed')) {
          _snack(
            'Google sign-in not enabled in Supabase yet. '
            'Go to Supabase → Auth → Providers → Google → Enable it.',
            color: DelightColors.gold);
        } else if (msg.contains('popup_closed') || msg.contains('cancelled')) {
          // User closed the popup — not an error
        } else {
          _snack(msg.replaceAll('Exception: ', '').replaceAll('AuthException: ', ''));
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {Color? color}) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color ?? DelightColors.error));

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) { _snack('Enter your email above first'); return; }
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.delight://reset-password/');
      _snack('Reset link sent to $email', color: DelightColors.emerald);
    } catch (e) {
      _snack('Could not send reset email');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _quickLogin(UserRole role, String name) {
    setState(() => _loading = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      final user = UserModel(
        id: 'usr_${role.name}',
        username: name.toLowerCase().replaceAll(' ', '_'),
        displayName: name,
        email: '${role.name}@delight.africa',
        role: role,
        createdAt: DateTime.now(),
      );
      ref.read(authProvider.notifier).login(user);
      if (mounted) context.go('/feed');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DelightColors.background,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Image.asset(
              'assets/images/delight_logo.png',
              height: 52,
              fit: BoxFit.contain),
              const SizedBox(height: 48),
              const Text('Welcome back', style: TextStyle(
                fontFamily: 'Clash', fontSize: 30, fontWeight: FontWeight.w700,
                color: DelightColors.textPrimary,
              )),
              const SizedBox(height: 6),
              const Text('Sign in to your Delight account', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 15, color: DelightColors.textSecondary,
              )),
              const SizedBox(height: 40),

              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontFamily: 'Satoshi', color: DelightColors.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined, color: DelightColors.textMuted, size: 20),
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                style: const TextStyle(fontFamily: 'Satoshi', color: DelightColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline, color: DelightColors.textMuted, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: DelightColors.textMuted, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Forgot password?', style: TextStyle(
                    fontFamily: 'Satoshi', color: DelightColors.gold, fontSize: 13,
                  )),
                ),
              ),
              const SizedBox(height: 24),

              // Role selector
              const Text('Sign in as', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 12, fontWeight: FontWeight.w600,
                color: DelightColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(children: [
                _roleBtn(UserRole.consumer,  '👤', 'Consumer'),
                const SizedBox(width: 6),
                _roleBtn(UserRole.business,  '🏪', 'Business'),
                const SizedBox(width: 6),
                _roleBtn(UserRole.organizer, '🎪', 'Organiser'),
                const SizedBox(width: 6),
                _roleBtn(UserRole.admin,     '🔑', 'Admin'),
              ]),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: _loading ? null : _login,
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: DelightColors.emeraldGradient),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                      color: DelightColors.emerald.withOpacity(0.35),
                      blurRadius: 20, offset: const Offset(0, 6),
                    )],
                  ),
                  alignment: Alignment.center,
                  child: _loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(
                        color: DelightColors.textInverse, strokeWidth: 2.5))
                    : const Text('Sign In', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 17, fontWeight: FontWeight.w700,
                        color: DelightColors.textInverse)),
                ),
              ),
              const SizedBox(height: 12),

              // ── OR divider ───────────────────────────────────────────
              Row(children: [
                Expanded(child: Divider(color: DelightColors.surfaceBorder)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(
                    fontFamily: 'Satoshi', fontSize: 13,
                    color: DelightColors.textMuted))),
                Expanded(child: Divider(color: DelightColors.surfaceBorder)),
              ]),
              const SizedBox(height: 12),

              // ── Google Sign-In ────────────────────────────────────────
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _loading ? null : _googleSignIn,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8, offset: const Offset(0, 2))]),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      // Google G logo as text (replace with Image.asset once
                      // you add assets/icons/google.png to your project)
                      Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4285F4), Color(0xFF34A853)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight)),
                        alignment: Alignment.center,
                        child: const Text('G', style: TextStyle(
                          fontFamily: 'Satoshi', fontWeight: FontWeight.w800,
                          fontSize: 14, color: Colors.white))),
                      const SizedBox(width: 12),
                      const Text('Continue with Google',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 15,
                          fontWeight: FontWeight.w700, color: Colors.black87)),
                    ])))),
              const SizedBox(height: 16),

              const SizedBox(height: 24),

              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text("Don't have an account? ", style: TextStyle(
                  fontFamily: 'Satoshi', color: DelightColors.textSecondary, fontSize: 14)),
                GestureDetector(
                  onTap: () => context.go('/signup'),
                  child: const Text('Sign up', style: TextStyle(
                    fontFamily: 'Satoshi', color: DelightColors.emerald,
                    fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ]),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleBtn(UserRole role, String emoji, String label) {
    final sel = _selectedRole == role;
    final colors = {
      UserRole.admin: DelightColors.error,
      UserRole.organizer: DelightColors.gold,
      UserRole.business: DelightColors.blue,
      UserRole.consumer: DelightColors.emerald,
    };
    final color = colors[role] ?? DelightColors.emerald;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.15) : DelightColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? color : DelightColors.surfaceBorder,
            width: sel ? 1.5 : 1)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontFamily: 'Satoshi', fontSize: 9,
            fontWeight: FontWeight.w700,
            color: sel ? color : DelightColors.textMuted)),
        ]))));
  }

  Widget _quickBtn(String label, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: DelightColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DelightColors.surfaceBorder)),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(
          fontFamily: 'Satoshi', fontSize: 11,
          fontWeight: FontWeight.w600, color: DelightColors.textSecondary)))));
  }
}
