import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/license_service.dart';
import 'widgets.dart';

/// Shown on first run (read-only) and reachable from Settings. The keeper reads
/// the device code to the owner and types back the activation key.
class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key, this.onDone});
  final VoidCallback? onDone;
  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final key = TextEditingController();
  String code = '...';
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    LicenseService.deviceCode().then((c) {
      if (mounted) setState(() => code = c);
    });
  }

  Future<void> _activate() async {
    setState(() => (busy = true, error = null));
    final ok = await LicenseService.activate(key.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) {
      snack(context, 'تم التفعيل بنجاح');
      widget.onDone?.call();
    } else {
      setState(() => error = 'المفتاح غير صحيح لهذا الجهاز. تأكد إنك بعت كود الجهاز الظاهر فوق.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تفعيل البرنامج')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.verified_user_outlined, size: 56, color: kIn),
                const SizedBox(height: 12),
                const Text('البرنامج يحتاج تفعيل لمرة واحدة', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('ابعت «كود الجهاز» للمسؤول، وهيرجعلك «مفتاح التفعيل». بعد التفعيل البرنامج يشتغل عادي على الجهاز ده من غير إنترنت.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      const Text('كود الجهاز', style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 6),
                      SelectableText(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2), textDirection: TextDirection.ltr),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          snack(context, 'اتنسخ كود الجهاز');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('نسخ الكود'),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: key,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 18, letterSpacing: 2),
                  decoration: InputDecoration(labelText: 'مفتاح التفعيل', errorText: error, hintText: 'XXXXX-XXXXX-XXXXX-XXXXX'),
                  onSubmitted: (_) => _activate(),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : _activate,
                  icon: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: const Text('تفعيل'),
                ),
                if (widget.onDone != null) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: widget.onDone, child: const Text('دخول بوضع القراءة فقط')),
                ],
              ]),
            ),
          ),
        ),
      );
}
