import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import 'common.dart';

/* ============================================================================
   FR-3.6 — what a part looks like.

   The first time a part is packed, Start Packing asks the operator to
   photograph it; every shift after that the photographs are what the next
   person checks against. Asked once per PART: the queue's `part_has_photos`
   is what stops the second ask, and it is keyed by the part number exactly
   as the GRN carries it (migration 234).
   ========================================================================== */

/// What has been photographed for one part. Auto-disposed so a gallery opened
/// again reads afresh rather than showing what was there an hour ago.
final partPhotosProvider = FutureProvider.autoDispose.family<List<PartPhoto>, String>(
  (ref, partNo) => ref.watch(repositoryProvider).partPhotos(partNo),
);

/// One photograph's bytes. A provider rather than a Future in build(), for the
/// reason given on labelPreviewProvider: a Future built in build() is a new
/// request on every rebuild.
final partPhotoBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, ({String partNo, String id})>(
  (ref, key) => ref.watch(repositoryProvider).partPhotoBytes(key.partNo, key.id),
);

/// Matches the server's cap (SPD_MAX_PHOTOS_PER_UPLOAD) — a face, a marking,
/// the box it came in.
const maxPhotosPerUpload = 6;

/// How the capture prompt ended.
enum PhotoPrompt { saved, skipped, cancelled }

typedef _Picked = ({String filename, String mime, Uint8List bytes});

/// A tablet camera writes a 12-megapixel frame; nobody needs one to recognise
/// a filter. Downscaled on the device (a canvas, on the web) before it is sent,
/// which keeps a shop-floor upload to a few hundred KB a photograph.
const double _maxEdge = 1600;
const int _quality = 80;

String _mimeOf(XFile f) {
  final m = f.mimeType;
  if (m != null && m.startsWith('image/') && m.split('/').length == 2) return m;
  final ext = f.name.split('.').last.toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    _ => 'image/jpeg',
  };
}

/// Asks for photographs of [partNo] before packing starts, and uploads them.
///
/// [PhotoPrompt.skipped] lets the floor keep moving when the camera will not
/// cooperate; nothing is stored, so the part is asked about again next time.
Future<PhotoPrompt> promptPartPhotos(
  BuildContext context,
  WidgetRef ref, {
  required String partNo,
  String partDesc = '',
}) async {
  final picker = ImagePicker();
  final hasCamera = picker.supportsImageSource(ImageSource.camera);
  final picked = <_Picked>[];
  var busy = false;
  String? error;

  Future<void> add(void Function(void Function()) setState, {required bool camera}) async {
    try {
      final files = camera
          ? [
              ?await picker.pickImage(
                source: ImageSource.camera,
                maxWidth: _maxEdge,
                maxHeight: _maxEdge,
                imageQuality: _quality,
              ),
            ]
          : await picker.pickMultiImage(maxWidth: _maxEdge, maxHeight: _maxEdge, imageQuality: _quality);
      final room = maxPhotosPerUpload - picked.length;
      final taken = <_Picked>[
        for (final f in files.take(room)) (filename: f.name, mime: _mimeOf(f), bytes: await f.readAsBytes()),
      ];
      setState(() {
        picked.addAll(taken);
        error = files.length > room ? 'Up to $maxPhotosPerUpload photographs at a time — the rest were left out.' : null;
      });
    } catch (e) {
      // A refused camera permission lands here; say so rather than nothing.
      setState(() => error = 'Could not get a photograph: $e');
    }
  }

  final result = await showSpdModal<PhotoPrompt>(
    context,
    dismissible: false,
    title: 'Photograph $partNo',
    subtitle: 'First time this part is packed — take one or more photographs so the next '
        'person can check they have the right thing.${partDesc.isEmpty ? '' : '  ·  $partDesc'}',
    content: (context, setState) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (hasCamera)
          GhostButton(
            label: 'Take photo',
            icon: Icons.photo_camera_outlined,
            small: false,
            onPressed: busy || picked.length >= maxPhotosPerUpload ? null : () => add(setState, camera: true),
          ),
        GhostButton(
          label: hasCamera ? 'Choose from gallery' : 'Choose files',
          icon: Icons.photo_library_outlined,
          small: false,
          onPressed: busy || picked.length >= maxPhotosPerUpload ? null : () => add(setState, camera: false),
        ),
      ]),
      const SizedBox(height: 14),
      if (picked.isEmpty)
        Container(
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Brand.surface2, borderRadius: BorderRadius.circular(Brand.rSm)),
          child: Text('No photographs yet', style: body(size: 12, color: Brand.txt3)),
        )
      else
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (i, p) in picked.indexed)
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Brand.rSm),
                child: Image.memory(p.bytes, width: 120, height: 120, fit: BoxFit.cover, cacheWidth: 240),
              ),
              if (!busy)
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => setState(() => picked.removeAt(i)),
                  ),
                ),
            ]),
        ]),
      if (error != null) ...[
        const SizedBox(height: 12),
        AlertBox(tone: AlertTone.bad, title: 'Photographs not saved', message: error!),
      ],
    ]),
    actions: (context, setState) => [
      GhostButton(
        label: 'Cancel',
        onPressed: busy ? null : () => Navigator.pop(context, PhotoPrompt.cancelled),
      ),
      GhostButton(
        label: 'Skip — ask next time',
        onPressed: busy ? null : () => Navigator.pop(context, PhotoPrompt.skipped),
      ),
      GradButton(
        label: busy
            ? 'Saving…'
            : picked.isEmpty
                ? 'Save & start'
                : 'Save ${picked.length} & start',
        icon: Icons.cloud_upload_outlined,
        onPressed: busy || picked.isEmpty
            ? null
            : () async {
                setState(() {
                  busy = true;
                  error = null;
                });
                try {
                  await ref.read(repositoryProvider).uploadPartPhotos(partNo, picked);
                  ref.invalidate(partPhotosProvider(partNo));
                  if (context.mounted) Navigator.pop(context, PhotoPrompt.saved);
                } on ApiException catch (e) {
                  setState(() {
                    busy = false;
                    error = e.message;
                  });
                }
              },
      ),
    ],
  );
  return result ?? PhotoPrompt.cancelled;
}

/// Every photograph of [partNos], newest last. Several part numbers because a
/// master code is a family and the GRN carries the variant: the Part Master
/// shows the photographs of every variant its lines carried.
class PartPhotoGallery extends ConsumerWidget {
  const PartPhotoGallery({super.key, required this.partNos});

  final List<String> partNos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider).user?.roleKey;
    // The server's canRemovePhoto: a correction, not a step in the packing.
    final canDelete = role == 'admin' || role == 'supervisor';

    final photos = <PartPhoto>[];
    var loading = false;
    Object? failure;
    for (final p in partNos) {
      ref.watch(partPhotosProvider(p)).when(
            data: photos.addAll,
            loading: () => loading = true,
            error: (e, _) => failure = e,
          );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PHOTOGRAPHS', style: eyebrow(size: 11, tracking: 1.3)),
      const SizedBox(height: 8),
      if (failure != null && photos.isEmpty)
        Text('Photographs could not be read: $failure', style: body(size: 12, color: Brand.txt3))
      else if (loading && photos.isEmpty)
        const SpdLoader(size: 32, fill: false)
      else if (photos.isEmpty)
        Text('None yet — the operator is asked for them the first time this part is packed.',
            style: body(size: 12, color: Brand.txt3))
      else
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in photos) _Thumb(photo: p, canDelete: canDelete, showPartNo: partNos.length > 1),
        ]),
    ]);
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.photo, required this.canDelete, required this.showPartNo});

  final PartPhoto photo;
  final bool canDelete;
  final bool showPartNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(partPhotoBytesProvider((partNo: photo.partNo, id: photo.id)));
    final box = BoxDecoration(color: Brand.surface2, borderRadius: BorderRadius.circular(Brand.rSm));

    return SizedBox(
      width: 140,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          bytes.when(
            loading: () => Container(width: 140, height: 140, decoration: box),
            error: (_, _) => Container(
              width: 140,
              height: 140,
              alignment: Alignment.center,
              decoration: box,
              child: Icon(Icons.broken_image_outlined, color: Brand.txt3),
            ),
            data: (b) => InkWell(
              onTap: () => _showFull(context, b),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Brand.rSm),
                child: Image.memory(b, width: 140, height: 140, fit: BoxFit.cover, cacheWidth: 280),
              ),
            ),
          ),
          if (canDelete)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove photograph',
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                onPressed: () => _delete(context, ref),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        if (showPartNo) Text(photo.partNo, style: mono(size: 11)),
        Text(
          '${photo.uploadedBy.isEmpty ? '—' : photo.uploadedBy} · ${fmtD(photo.uploadedAt)}',
          style: body(size: 11, color: Brand.txt3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ]),
    );
  }

  void _showFull(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(children: [
          InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(bytes))),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              tooltip: 'Close',
              color: Colors.white,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showSpdModal<bool>(
      context,
      title: 'Remove this photograph?',
      subtitle: '${photo.partNo} · taken by ${photo.uploadedBy.isEmpty ? '—' : photo.uploadedBy}. '
          'The removal is recorded in the audit log.',
      content: (_, _) => const SizedBox.shrink(),
      actions: (context, _) => [
        GhostButton(label: 'Keep', onPressed: () => Navigator.pop(context, false)),
        GhostButton(label: 'Remove', danger: true, onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).deletePartPhoto(photo.partNo, photo.id);
      ref.invalidate(partPhotosProvider(photo.partNo));
      if (context.mounted) Toast.ok(context, 'Photograph removed', photo.partNo);
    } on ApiException catch (e) {
      if (context.mounted) Toast.bad(context, 'Could not remove it', e.message);
    }
  }
}
