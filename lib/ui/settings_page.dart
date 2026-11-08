import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../services/license_service.dart';
import 'activation_page.dart';
import '../services/backup_service.dart';
import '../services/daily_service.dart';
import '../services/pdf_service.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final company = TextEditingController();
  final keeper = TextEditingController();
  String folder = '', sheetTime = DailyService.defaultTime;
  int count = 0;

  @override
  void initState() {
    super.initState();
    Repo.i.setting('company', 'شركة سان المتحدة للمقاولات العامة').then((v) => company.text = v);
    Repo.i.setting('keeper').then((v) => keeper.text = v);
    _refresh();
  }

  Future<void> _refresh() async {
    final f = await BackupService.folder();
    final n = (await BackupService.list()).length;
    final t = await DailyService.time();
    if (mounted) setState(() => (folder = f, count = n, sheetTime = t));
  }

  Future<void> _run(Future<bool> Function() f, String ok) async {
    try {
      if (await f() && mounted) snack(context, ok);
    } catch (e) {
      if (mounted) snack(context, '$e', error: true);
    }
    await _refresh();
  }

  Future<void> _pickTime() async {
    final p = sheetTime.split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
    if (t == null) return;
    String two(int v) => v.toString().padLeft(2, '0');
    await Repo.i.setSetting('sheet_time', '${two(t.hour)}:${two(t.minute)}');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => PageScaffold(
        title: 'الإعدادات',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListCard(title: 'الترخيص', children: [
            ListTile(
              leading: Icon(Repo.i.writable ? Icons.verified_user : Icons.lock_outline, color: Repo.i.writable ? Colors.green : Colors.orange),
              title: Text(Repo.i.writable ? 'البرنامج مفعّل على الجهاز ده' : 'وضع القراءة فقط — غير مفعّل'),
              subtitle: Text(Repo.i.writable ? 'يشتغل عادي من غير إنترنت' : 'اضغط للتفعيل'),
              trailing: Repo.i.writable ? null : const Icon(Icons.chevron_left),
              onTap: Repo.i.writable
                  ? null
                  : () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivationPage(onDone: () {
                            Repo.i.writable = LicenseService.activated;
                            Repo.i.notify();
                            Navigator.of(context).maybePop();
                          })));
                      if (mounted) setState(() {});
                    },
            ),
          ]),
          const SizedBox(height: 12),
          ListCard(title: 'بيانات الطباعة', children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(controller: company, decoration: const InputDecoration(labelText: 'اسم الشركة (بيظهر فوق في إذن الصرف)')),
                const SizedBox(height: 12),
                TextField(controller: keeper, decoration: const InputDecoration(labelText: 'اسم أمين المستودع (بيظهر في التوقيع)')),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    onPressed: () async {
                      await Repo.i.setSetting('company', company.text.trim());
                      await Repo.i.setSetting('keeper', keeper.text.trim());
                      if (context.mounted) snack(context, 'اتحفظت البيانات');
                    },
                    child: const Text('حفظ'),
                  ),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          ListCard(title: 'ورقة الجرد اليومي', children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('وقت تجهيز الورقة'),
              subtitle: const Text('وبتتجهز كمان لما تقفل البرنامج'),
              trailing: Text(sheetTime, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: _pickTime,
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('طباعة ورقة الجرد دلوقتي'),
              onTap: () => _run(() async {
                await PdfService.printBytes(await DailyService.sheetBytes(), 'ورقة الجرد');
                return false;
              }, ''),
            ),
          ]),
          const SizedBox(height: 12),
          ListCard(title: 'النسخ الاحتياطي', children: [
            ListTile(
              leading: const Icon(Icons.verified_user_outlined, color: Colors.green),
              title: const Text('نسخة تلقائية كل يوم، بالبيانات وصور الفواتير'),
              subtitle: Text('محفوظ $count من آخر ${BackupService.keep} نسخة'),
            ),
            ListTile(
              leading: Icon(Icons.folder_outlined, color: BackupService.onSystemDrive(folder) ? Colors.orange : null),
              title: const Text('مكان النسخ'),
              subtitle: Text(
                BackupService.onSystemDrive(folder) ? '$folder\nمفيش قرص تاني على الجهاز، فالنسخ على C' : folder,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.right,
              ),
              trailing: const Text('تغيير'),
              onTap: () async {
                final d = await FilePicker.getDirectoryPath(dialogTitle: 'اختار مكان النسخ', initialDirectory: folder);
                if (d == null) return;
                await Repo.i.setSetting('backup_dir', d);
                await _refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('اعمل نسخة دلوقتي'),
              subtitle: const Text('نسخة يدوية في مكان النسخ'),
              onTap: () => _run(() async {
                await BackupService.create('manual');
                return true;
              }, 'اتعملت النسخة الاحتياطية'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('حفظ نسخة في مكان تاني'),
              subtitle: const Text('فلاشة أو OneDrive'),
              onTap: () => _run(BackupService.exportBackup, 'اتحفظت النسخة الاحتياطية'),
            ),
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.orange),
              title: const Text('استرجاع نسخة احتياطية'),
              subtitle: const Text('هيستبدل البيانات الحالية بالنسخة اللي تختارها'),
              onTap: () async {
                if (!await confirm(context, 'استرجاع نسخة', 'البيانات الحالية هتتستبدل بالنسخة اللي هتختارها. هحفظ نسخة من الحالية الأول. تكمل؟', ok: 'استرجاع')) return;
                await _run(BackupService.restore, 'اترجعت النسخة بنجاح');
              },
            ),
            if (Platform.isWindows)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('فتح فولدر النسخ'),
                subtitle: const Text('النسخ التلقائية واليدوية وأوراق الجرد'),
                onTap: () async => Process.run('explorer', [await BackupService.usableFolder()]),
              ),
          ]),
        ]),
      );
}
