import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// UC-10 / FR-13.1 & FR-13.3 — user accounts, roles and what each role reaches.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  PillTone _roleTone(String role) => switch (role) {
        'Supervisor' => PillTone.pink,
        'Administrator' => PillTone.violet,
        'Member' => PillTone.info,
        _ => PillTone.neutral,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(usersProvider);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        crumb: 'Admin ·',
        accent: 'Users',
        title: 'Users & role-based access',
        blurb: 'Role-based access control restricts every user class to its permitted screens '
            '(FR-13.3). Table Member login is a simplified name/ID selection with a PIN, suited to '
            'the shop floor (NFR-3.1).',
        actions: [
          GradButton(
            label: 'Add user',
            icon: Icons.person_add_alt_1_rounded,
            small: true,
            onPressed: () => _editUser(context, ref, null),
          ),
        ],
      ),
      async.when(
        skipLoadingOnReload: true,
        loading: () => const SpdLoader(size: 48),
        error: (e, _) => ErrorPanel(message: '$e', onRetry: () => invalidateAll(ref)),
        data: (users) => SpdTable(
          columns: const [
            SpdCol('Name', width: 200),
            SpdCol('Login ID', width: 130),
            SpdCol('Employee', width: 116),
            SpdCol('Role', width: 148),
            SpdCol('Table / Device', width: 170),
            SpdCol('Email', width: 230),
            SpdCol('Access', width: 280, wrap: true),
            SpdCol('', right: true, width: 96),
          ],
          rows: [
            for (final u in users)
              SpdRow([
                Opacity(opacity: u.active ? 1 : 0.5, child: personCell(u.name)),
                monoCell(u.id),
                monoCell(u.empCode),
                Pill(u.role, tone: _roleTone(u.role)),
                monoCell('${u.tableNo != null ? '${u.tableNo} · ' : ''}${u.device.isEmpty ? '—' : u.device}'),
                cell(u.email.isEmpty ? '—' : u.email),
                wrapCell(u.access),
                GhostButton(label: 'Edit', onPressed: () => _editUser(context, ref, u)),
              ]),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const AlertBox(
        tone: AlertTone.info,
        title: 'NFR-3.3 — every change here is audit-logged',
        message: 'Account creation, role changes, deactivation and credential resets are all '
            'recorded with the administrator, the timestamp and what changed.',
      ),
    ]);
  }

  /// One dialog for both create and edit — the fields differ only in whether the
  /// login ID is still editable.
  Future<void> _editUser(BuildContext context, WidgetRef ref, SpdUser? existing) async {
    final isNew = existing == null;
    final id = TextEditingController(text: existing?.id ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final emp = TextEditingController(text: existing?.empCode ?? '');
    final email = TextEditingController(text: existing?.email ?? '');
    final device = TextEditingController(text: existing?.device ?? '');
    final secret = TextEditingController();
    var role = existing?.role ?? 'Member';
    var active = existing?.active ?? true;

    await showSpdModal<void>(
      context,
      title: isNew ? 'Add user' : 'Edit ${existing.name}',
      subtitle: isNew ? 'FR-13.1 · a new account starts active' : existing.id,
      content: (context, setModalState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isNew)
          Field(
            label: 'Login ID',
            required: true,
            child: TextField(
              controller: id,
              style: body(size: 14),
              decoration: const InputDecoration(hintText: 'e.g. tm.rsharma'),
            ),
          ),
        Field(
          label: 'Full name',
          required: true,
          child: TextField(controller: name, style: body(size: 14)),
        ),
        Row(children: [
          Expanded(
            child: Field(
              label: 'Employee code',
              required: true,
              child: TextField(
                controller: emp,
                enabled: isNew,
                style: mono(size: 14),
                decoration: const InputDecoration(hintText: 'EMP-0000'),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Field(
              label: 'Role',
              child: SpdDropdown<String>(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'Supervisor', child: Text('Supervisor')),
                  DropdownMenuItem(value: 'Member', child: Text('Table Member')),
                  DropdownMenuItem(value: 'Administrator', child: Text('Administrator')),
                  DropdownMenuItem(value: 'Management', child: Text('Management')),
                ],
                onChanged: (v) => setModalState(() => role = v ?? role),
              ),
            ),
          ),
        ]),
        Row(children: [
          Expanded(child: Field(label: 'Email', child: TextField(controller: email, style: body(size: 14)))),
          const SizedBox(width: 14),
          Expanded(
            child: Field(
              label: 'Device',
              child: TextField(
                controller: device,
                style: body(size: 14),
                decoration: const InputDecoration(hintText: 'TAB-T1'),
              ),
            ),
          ),
        ]),
        Field(
          label: role == 'Member' ? 'PIN' : 'Password',
          required: isNew,
          hint: isNew
              ? (role == 'Member'
                  ? 'A short numeric PIN suits a shared table device (NFR-3.1).'
                  : 'The user changes this at first sign-in.')
              : 'Leave blank to keep the existing credential.',
          child: TextField(controller: secret, obscureText: true, style: body(size: 14)),
        ),
        if (!isNew)
          Row(children: [
            Switch(value: active, onChanged: (v) => setModalState(() => active = v)),
            const SizedBox(width: 8),
            Text(active ? 'Active' : 'Deactivated', style: body(size: 13)),
          ]),
      ]),
      actions: (context, _) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        GradButton(
          label: isNew ? 'Create user' : 'Save changes',
          icon: Icons.check_rounded,
          small: true,
          onPressed: () async {
            try {
              final repo = ref.read(repositoryProvider);
              final isMember = role == 'Member';
              if (isNew) {
                await repo.createUser({
                  'id': id.text.trim(),
                  'name': name.text.trim(),
                  'empCode': emp.text.trim(),
                  'role': role,
                  'email': email.text.trim(),
                  'device': device.text.trim(),
                  if (isMember) 'pin': secret.text else 'password': secret.text,
                });
              } else {
                await repo.updateUser(existing.id, {
                  'name': name.text.trim(),
                  'role': role,
                  'email': email.text.trim(),
                  'device': device.text.trim(),
                  'active': active,
                  if (secret.text.isNotEmpty && isMember) 'pin': secret.text,
                  if (secret.text.isNotEmpty && !isMember) 'password': secret.text,
                });
              }
              if (context.mounted) Navigator.pop(context);
              invalidateAll(ref);
              if (context.mounted) {
                Toast.ok(context, isNew ? 'User created' : 'User updated',
                    '${name.text.trim()} · $role — recorded in the audit trail.');
              }
            } on ApiException catch (e) {
              if (context.mounted) Toast.bad(context, 'Could not save', e.message);
            }
          },
        ),
      ],
    );
  }
}
