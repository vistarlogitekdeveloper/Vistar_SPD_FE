import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import 'common.dart';

/// Who is standing at this bench, by name.
///
/// This used to be a picker on the sign-in screen, and it was the wrong screen
/// for it twice over. A member had to find themselves in a roster before they
/// could type a password, which on a tablet shared by a rotating floor is a
/// list they scroll past rather than read — and it could only ever name one
/// person, while a heavy shift puts two or three on one bench. Most of them
/// have no login at all: the floor rotates faster than the user list does.
///
/// So the question is asked after sign-in, at the table, of whoever is already
/// standing there — and it takes as many names as the bench holds. They are
/// free text on purpose. Nothing authenticates against them; they are what the
/// ID label prints as PACKER and what the Supervisor's seating panel shows.
///
/// Opened from two places: the shell, when a Member has just signed in, and
/// the seating panel, when a Supervisor is correcting a bench.
Future<bool> showOperatorPrompt(
  BuildContext context,
  WidgetRef ref, {
  required String tableNo,

  /// True when this is the sign-in prompt rather than a Supervisor's edit. It
  /// changes only the wording and whether the dialog can be waved away.
  bool atSignIn = false,
}) async {
  /* Both of these are awaited rather than read off whatever is cached, and
     the shift list is why. At sign-in this opens on the frame the member
     lands on, which is before anything has finished loading:
     [selectedShiftProvider] falls back to the newest shift in a list that is
     still in flight, so it answers null, and the prompt returned without
     asking — silently, which is the worst way for a dialog to be missing. */
  try {
    await ref.read(shiftsProvider.future);
  } catch (_) {
    return false;
  }
  if (!context.mounted) return false;

  final shiftId = ref.read(selectedShiftProvider);
  if (shiftId == null) return false;

  Map<String, List<String>> floor;
  try {
    floor = await ref.read(operatorsProvider.future);
  } on ApiException catch (e) {
    // A console deployed ahead of its backend (migration 215) gets a 404 here.
    // There is nothing to ask for until that lands, so it does not ask.
    if (e.statusCode == 404) return false;
    floor = const {};
  } catch (_) {
    floor = const {};
  }
  if (!context.mounted) return false;

  final existing = floor[tableNo] ?? const <String>[];
  // Nobody named yet, and we know who just signed in — so the common case is
  // one person at the bench confirming their own name, which should be a tap
  // rather than a typing exercise on a shop-floor keyboard.
  final me = ref.read(sessionProvider).user?.name.trim() ?? '';
  final names = <String>[
    ...existing,
    if (existing.isEmpty && atSignIn && me.isNotEmpty) me,
  ];

  final entry = TextEditingController();
  var saving = false;
  String? error;

  final saved = await showSpdModal<bool>(
    context,
    title: 'Who is working at $tableNo?',
    subtitle: atSignIn
        ? 'Add everyone on this bench for the shift. It goes on the ID labels you print.'
        : 'The names on this bench for the shift, as the floor entered them.',
    dismissible: !atSignIn,
    content: (context, setModalState) {
      void add(String raw) {
        final name = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (name.isEmpty) return;
        // Folded the same way the server folds it, so the chip list on screen
        // and the row list in the database cannot disagree about duplicates.
        if (names.any((n) => n.toLowerCase() == name.toLowerCase())) {
          setModalState(() {
            entry.clear();
            error = '$name is already on this bench';
          });
          return;
        }
        if (names.length >= 8) {
          setModalState(() => error = 'A bench holds up to eight people');
          return;
        }
        setModalState(() {
          names.add(name);
          entry.clear();
          error = null;
        });
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (names.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Nobody named yet.',
              style: body(size: 13, color: Brand.txt3),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in names)
                _OperatorChip(
                  name: n,
                  onRemove: saving
                      ? null
                      : () => setModalState(() {
                            names.remove(n);
                            error = null;
                          }),
                ),
            ]),
          ),

        Field(
          label: 'Add a name',
          hint: 'Type it and press Enter. Remove one with the × on its chip.',
          bottom: 0,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: entry,
                enabled: !saving,
                autofocus: true,
                // A shop-floor tablet's keyboard offering the last person who
                // stood here is the autofill this screen was asked to stop
                // doing — on the sign-in screen, for the same reason.
                autocorrect: false,
                autofillHints: const [],
                enableSuggestions: false,
                textCapitalization: TextCapitalization.words,
                style: body(size: 14),
                decoration: const InputDecoration(hintText: 'e.g. Anita Varma'),
                onSubmitted: add,
              ),
            ),
            const SizedBox(width: 8),
            IconTile(
              icon: Icons.add_rounded,
              tooltip: 'Add this name',
              onTap: saving ? null : () => add(entry.text),
            ),
          ]),
        ),

        if (error != null) ...[
          const SizedBox(height: 14),
          AlertBox(tone: AlertTone.warn, title: 'Not added', message: error!),
        ],
      ]);
    },
    actions: (context, setModalState) => [
      GhostButton(
        label: atSignIn ? 'Not now' : 'Cancel',
        onPressed: saving ? null : () => Navigator.pop(context, false),
      ),
      GradButton(
        label: saving ? 'Saving…' : 'Save',
        icon: Icons.check_rounded,
        small: true,
        onPressed: saving
            ? null
            : () async {
                /* The field is allowed to still hold a name. Someone who types
                   the last one and goes straight for Save has said what they
                   mean, and losing it to an unpressed Enter is the kind of
                   small betrayal that makes a screen feel broken. */
                final pending = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();
                final out = [
                  ...names,
                  if (pending.isNotEmpty &&
                      !names.any((n) => n.toLowerCase() == pending.toLowerCase()))
                    pending,
                ];
                setModalState(() {
                  saving = true;
                  error = null;
                });
                try {
                  await ref.read(repositoryProvider).saveTableOperators(shiftId, tableNo, out);
                  ref.invalidate(operatorsProvider);
                  if (context.mounted) Navigator.pop(context, true);
                } on ApiException catch (e) {
                  setModalState(() {
                    saving = false;
                    error = e.message;
                  });
                }
              },
      ),
    ],
  );

  return saved ?? false;
}

class _OperatorChip extends StatelessWidget {
  const _OperatorChip({required this.name, required this.onRemove});

  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        decoration: BoxDecoration(
          color: Brand.pink.withValues(alpha: 0.13),
          border: Border.all(color: Brand.pink.withValues(alpha: 0.32)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(name, style: body(size: 13, weight: FontWeight.w700)),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 14),
            color: Brand.txt3,
            splashRadius: 14,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            tooltip: 'Remove $name',
          ),
        ]),
      );
}

/// The names at a bench, drawn small — for the seating panel and anywhere else
/// that shows a table without being the place you edit it.
class OperatorNames extends ConsumerWidget {
  const OperatorNames({super.key, required this.tableNo, this.onEdit});

  final String tableNo;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A console in front of a backend that has not taken migration 215 yet
    // gets a 404 here. This is additive to every screen it appears on, so it
    // shows nothing rather than an error nobody on the floor can act on.
    final names = ref.watch(operatorsProvider).value?[tableNo] ?? const <String>[];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Text(
          names.isEmpty ? 'Nobody named' : names.join(' · '),
          style: body(
            size: 12,
            color: names.isEmpty ? Brand.txt3 : Brand.txt2,
            height: 1.45,
          ),
        ),
      ),
      if (onEdit != null) ...[
        const SizedBox(width: 6),
        IconTile(
          icon: Icons.group_outlined,
          tooltip: 'Name the people at $tableNo',
          size: 28,
          onTap: onEdit,
        ),
      ],
    ]);
  }
}
