import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _signIn() async {
    setState(() { _busy = true; _err = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() { _err = e.message; });
    } finally {
      setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Merchant Sign In',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(controller: _email, decoration: const InputDecoration(
                  labelText: 'Email',
                )),
                const SizedBox(height: 8),
                TextField(controller: _pass, obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password')),
                const SizedBox(height: 12),
                if (_err != null)
                  Text(_err!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy ? const CircularProgressIndicator() : const Text('Sign in'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
