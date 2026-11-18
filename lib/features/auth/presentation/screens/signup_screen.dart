import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/supabase_service.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading  = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose();
    _passwordCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name     = _nameCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm  = _confirmCtrl.text;

    if (name.isEmpty)  { _setError('Please enter your name'); return; }
    if (email.isEmpty) { _setError('Please enter your email'); return; }
    if (!email.contains('@')) { _setError('Enter a valid email'); return; }
    if (password.length < 8) { _setError('Password must be at least 8 characters'); return; }
    if (password != confirm) { _setError('Passwords do not match'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      final result = await SupabaseService.signUp(
        email: email,
        password: password,
        displayName: name,
        username: email.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
        role: 'consumer',
      );
      if (mounted) {
        if (result.needsConfirmation) {
          // Confirmation email sent — but also try signing in immediately
          // in case email confirmation was disabled in Supabase settings
          try {
            await SupabaseService.signIn(email: email, password: password);
            context.go('/feed');
          } catch (_) {
            // Sign in failed = confirmation truly required
            _showVerifyEmail(email);
          }
        } else {
          context.go('/feed');
        }
      }
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', '').replaceAll('AuthException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignUp() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Web: OAuth redirect — same flow as sign-in, Google handles new vs existing
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.toString(),
      );
      // Page will redirect — no need to navigate manually
    } catch (e) {
      _setError(e.toString().replaceAll('Exception: ', ''));
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setError(String msg) => setState(() => _error = msg);

  void _showVerifyEmail(String email) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DelightColors.surfaceHigh,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          bool resent = false;
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📧', style: TextStyle(fontSize: 52)),
              const SizedBox(height: 16),
              const Text('Confirm your email',
                style: TextStyle(fontFamily: 'Clash', fontSize: 24,
                  fontWeight: FontWeight.w700, color: DelightColors.textPrimary)),
              const SizedBox(height: 10),
              RichText(textAlign: TextAlign.center, text: TextSpan(children: [
                const TextSpan(text: 'A confirmation link was sent to\n',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                    color: DelightColors.textSecondary, height: 1.5)),
                TextSpan(text: email,
                  style: const TextStyle(fontFamily: 'Satoshi', fontSize: 14,
                    fontWeight: FontWeight.w700, color: DelightColors.emerald)),
              ])),
              const SizedBox(height: 10),
              const Text(
                'Check your inbox and spam/junk folder.\nClick the link in the email to activate your account.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                  color: DelightColors.textMuted, height: 1.5)),
              const SizedBox(height: 6),
              const Text(
                '⚠️ If no email arrives within 2 minutes, check spam or use a different email address.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.gold, height: 1.4)),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(context);
                      context.go('/login');
                    },
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: DelightColors.emeraldGradient),
                        borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: const Text('I confirmed — Sign In',
                        style: TextStyle(fontFamily: 'Satoshi', fontSize: 15,
                          fontWeight: FontWeight.w800, color: Colors.white)))))),
              const SizedBox(height: 10),
              // Resend button
              TextButton(
                onPressed: resent ? null : () async {
                  try {
                    await Supabase.instance.client.auth.resend(
                      type: OtpType.signup, email: email);
                    setModal(() => resent = true);
                  } catch (_) {}
                },
                child: Text(
                  resent ? '✓ Email resent' : 'Resend confirmation email',
                  style: TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                    color: resent ? DelightColors.emerald : DelightColors.textMuted))),
              const SizedBox(height: 8),
            ]));
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: DelightColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            // Back
            GestureDetector(
              onTap: () => context.go('/login'),
              child: const Icon(Icons.arrow_back,
                color: DelightColors.textMuted, size: 22)),
            const SizedBox(height: 24),
            // Header
            Image.asset(
              'assets/images/delight_logo.png',
              height: 52,
              fit: BoxFit.contain),
            const SizedBox(height: 20),
            const Text('Create account', style: TextStyle(
              fontFamily: 'Clash', fontSize: 28, fontWeight: FontWeight.w700,
              color: DelightColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Join Delight — pay, connect, celebrate.', style: TextStyle(
              fontFamily: 'Satoshi', fontSize: 14, color: DelightColors.textSecondary)),
            const SizedBox(height: 28),

            // Google Sign Up
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _loading ? null : _googleSignUp,
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
                    const Text('Sign up with Google', style: TextStyle(
                      fontFamily: 'Satoshi', fontSize: 15,
                      fontWeight: FontWeight.w700, color: Colors.black87)),
                  ]))),
            ),
            const SizedBox(height: 16),

            // OR divider
            Row(children: [
              const Expanded(child: Divider(color: DelightColors.surfaceBorder)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or sign up with email', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 12,
                  color: DelightColors.textMuted))),
              const Expanded(child: Divider(color: DelightColors.surfaceBorder)),
            ]),
            const SizedBox(height: 16),

            // Name
            _field('Full Name', _nameCtrl, Icons.person_outline),
            const SizedBox(height: 12),
            // Email
            _field('Email', _emailCtrl, Icons.email_outlined,
              type: TextInputType.emailAddress),
            const SizedBox(height: 12),
            // Password
            _passField('Password', _passwordCtrl, _obscure1,
              () => setState(() => _obscure1 = !_obscure1)),
            const SizedBox(height: 12),
            // Confirm
            _passField('Confirm Password', _confirmCtrl, _obscure2,
              () => setState(() => _obscure2 = !_obscure2)),
            const SizedBox(height: 8),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DelightColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DelightColors.error.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                    color: DelightColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                    style: const TextStyle(fontFamily: 'Satoshi', fontSize: 13,
                      color: DelightColors.error))),
                ])),
            ],
            const SizedBox(height: 24),

            // Sign Up button
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _loading ? null : _signUp,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: DelightColors.emeraldGradient),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                      color: DelightColors.emerald.withOpacity(0.35),
                      blurRadius: 20, offset: const Offset(0, 6))]),
                  alignment: Alignment.center,
                  child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                    : const Text('Create Account', style: TextStyle(
                        fontFamily: 'Satoshi', fontSize: 16,
                        fontWeight: FontWeight.w800, color: Colors.white))))),
            const SizedBox(height: 20),

            // Already have account
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Already have an account? ', style: TextStyle(
                fontFamily: 'Satoshi', fontSize: 14,
                color: DelightColors.textMuted)),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text('Sign In', style: TextStyle(
                  fontFamily: 'Satoshi', fontSize: 14,
                  fontWeight: FontWeight.w700, color: DelightColors.emerald))),
            ]),
            const SizedBox(height: 32),
          ]))));
  }

  Widget _field(String label, TextEditingController ctrl, IconData icon,
      {TextInputType type = TextInputType.text}) =>
    TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontFamily: 'Satoshi',
        color: DelightColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: DelightColors.textMuted, size: 18),
        filled: true, fillColor: DelightColors.surfaceHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.emerald, width: 1.5))));

  Widget _passField(String label, TextEditingController ctrl,
      bool obscure, VoidCallback toggle) =>
    TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontFamily: 'Satoshi',
        color: DelightColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline,
          color: DelightColors.textMuted, size: 18),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
            color: DelightColors.textMuted, size: 18),
          onPressed: toggle),
        filled: true, fillColor: DelightColors.surfaceHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.surfaceBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: DelightColors.emerald, width: 1.5))));
}
