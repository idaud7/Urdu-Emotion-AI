import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  UserRole _selectedRole = UserRole.user;
  String? _selectedGender; // 'Male', 'Female', 'Prefer not to say'
  bool _obscurePassword = true;
  bool _loading = false;
  bool _isSignUp = false;
  bool _tosAgreed = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Auth action ────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isSignUp && !_tosAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please read and agree to the Terms, Privacy Policy, and Consent before continuing.'),
          backgroundColor: AppColors.angry,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    String? error;
    if (_isSignUp) {
      error = await AuthService.instance.signUp(
        email,
        password,
        displayName: _nameController.text.trim(),
        age: int.tryParse(_ageController.text.trim()),
        gender: _selectedGender,
      );
    } else {
      error = await AuthService.instance.login(
        email,
        password,
        _selectedRole,
      );
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.angry,
        ),
      );
      return;
    }

    if (_isSignUp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created successfully.'),
          backgroundColor: AppColors.primary,
        ),
      );
      context.go('/home');
    } else {
      if (_selectedRole == UserRole.admin) {
        context.go('/admin');
      } else {
        context.go('/home');
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isAdmin = _selectedRole == UserRole.admin;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surface, AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 48),

                              // ── Header ──
                  Text(
                    _isSignUp ? 'Create account' : 'Welcome back',
                    style: Theme.of(context)
                        .textTheme
                        .displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSignUp
                        ? 'Sign up to start using Urdu Emotion AI'
                        : 'Sign in to continue to Urdu Emotion AI',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 36),

                  // ── Role toggle (sign-in only) ──
                  if (!_isSignUp) ...[
                    _RoleToggle(
                      selected: _selectedRole,
                      onChanged: (r) {
                        setState(() {
                          _selectedRole = r;
                          if (r == UserRole.admin) _isSignUp = false;
                        });
                      },
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── Sign-up extra fields ──
                  if (_isSignUp) ...[
                    // Full Name
                    TextFormField(
                      controller: _nameController,
                      keyboardType: TextInputType.name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon:
                            Icon(Icons.badge_outlined, size: 20),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Full name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Age
                    TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        prefixIcon:
                            Icon(Icons.cake_outlined, size: 20),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Age is required';
                        }
                        final age = int.tryParse(v.trim());
                        if (age == null || age < 1 || age > 120) {
                          return 'Please enter a valid age';
                        }
                        if (age < 13) {
                          return 'You must be at least 13 years old to use this app';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Gender
                    _GenderSelector(
                      selected: _selectedGender,
                      onChanged: (g) =>
                          setState(() => _selectedGender = g),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Email / Username field ──
                  TextFormField(
                    controller: _emailController,
                    keyboardType: isAdmin
                        ? TextInputType.text
                        : TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: isAdmin ? 'Username' : 'Email Address',
                      prefixIcon:
                          const Icon(Icons.email_outlined, size: 20),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return isAdmin
                            ? 'Username is required'
                            : 'Email address is required';
                      }
                      if (!isAdmin && !v.contains('@')) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Password field ──
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon:
                          const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: AppColors.onSurface,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Password is required';
                      }
                      if (_isSignUp && v.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Terms, Privacy & Consent (sign-up only) ──
                  if (_isSignUp) ...[
                    _TosWidget(
                      agreed: _tosAgreed,
                      onAgreedChanged: (v) =>
                          setState(() => _tosAgreed = v ?? false),
                    ),
                    const SizedBox(height: 28),
                  ] else
                    const SizedBox(height: 4),

                  // ── Primary button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isSignUp
                              ? 'Create account'
                              : isAdmin
                                  ? 'Sign in as Admin'
                                  : 'Sign in as User'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Toggle login / signup (user role only) ──
                  if (!isAdmin)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isSignUp
                              ? 'Already have an account?'
                              : "Don't have an account?",
                          style:
                              Theme.of(context).textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    _isSignUp = !_isSignUp;
                                    _tosAgreed = false;
                                    _selectedGender = null;
                                    _nameController.clear();
                                    _ageController.clear();
                                  }),
                          child: Text(
                            _isSignUp ? 'Sign in' : 'Sign up',
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
                  ),
                ),
              );
            },
          ),
              // ── Back button (top-left) ──
              Positioned(
                top: 0,
                left: 0,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: AppColors.onSurface),
                  onPressed: () => context.go('/'),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Gender selector ──────────────────────────────────────────────────────────
class _GenderSelector extends StatelessWidget {
  const _GenderSelector(
      {required this.selected, required this.onChanged});
  final String? selected;
  final ValueChanged<String?> onChanged;

  static const _options = ['Male', 'Female', 'Prefer not to say'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _options.map((option) {
            final isSelected = selected == option;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: option == _options.last ? 0 : 8,
                ),
                child: GestureDetector(
                  onTap: () => onChanged(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      option,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : AppColors.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Terms of Service / Privacy / Consent widget ─────────────────────────────
class _TosWidget extends StatelessWidget {
  const _TosWidget(
      {required this.agreed, required this.onAgreedChanged});
  final bool agreed;
  final ValueChanged<bool?> onAgreedChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scrollable legal text
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Terms of Service ──
                  Text('Terms of Service',
                      style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _tosItem('You must be at least 13 years old to use this application.'),
                  _tosItem('Do not misuse the app for harmful, illegal, or unethical purposes.'),
                  _tosItem('All content, AI models, and features are the intellectual property of Urdu Emotion AI.'),
                  _tosItem('We are not liable for any decisions made based on AI emotion analysis results.'),
                  const SizedBox(height: 14),

                  // ── Privacy Policy / Data Use ──
                  Text('Privacy Policy & Data Use',
                      style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _tosItem('We collect voice recordings, emotion analysis results, and device/usage data to provide the service.'),
                  _tosItem('Your data is used solely to provide and improve emotion analysis features.'),
                  _tosItem('We do not sell your personal data to third parties.'),
                  _tosItem('Data is retained for as long as your account is active. You may request deletion at any time by contacting support.'),
                  _tosItem('You have the right to access, correct, or delete your personal data at any time.'),
                  const SizedBox(height: 14),

                  // ── Consent for Processing Sensitive Data ──
                  Text('Consent for Processing Sensitive Data',
                      style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _tosItem('By registering, you explicitly consent to the processing of your voice recordings for AI-based emotion analysis.'),
                  _tosItem('This app is not a medical device. Results must not be used for medical diagnosis or treatment.'),
                  _tosItem('Anonymized data may be used for research to improve emotion recognition models. You may opt out by contacting us.'),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Acknowledgement checkbox ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: agreed,
              onChanged: onAgreedChanged,
              activeColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => onAgreedChanged(!agreed),
                child: Text(
                  'I have read, understood, and agree to the Terms of Service, '
                  'Privacy Policy, and Consent for Processing Sensitive Data.',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tosItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(color: AppColors.onSurface, fontSize: 12)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 12,
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Role toggle ──────────────────────────────────────────────────────────────
class _RoleToggle extends StatelessWidget {
  const _RoleToggle({required this.selected, required this.onChanged});
  final UserRole selected;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _RoleTab(
            label: 'User',
            icon: Icons.person_outline,
            isActive: selected == UserRole.user,
            onTap: () => onChanged(UserRole.user),
          ),
          _RoleTab(
            label: 'Admin',
            icon: Icons.admin_panel_settings_outlined,
            isActive: selected == UserRole.admin,
            onTap: () => onChanged(UserRole.admin),
          ),
        ],
      ),
    );
  }
}

class _RoleTab extends StatelessWidget {
  const _RoleTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? Colors.white : AppColors.onSurface,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isActive ? Colors.white : AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
