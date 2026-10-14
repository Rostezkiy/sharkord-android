import 'package:flutter/material.dart';

import '../../helpers/file_url.dart';
import '../../models/server_file.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';

/// the circular avatar every list, message and member row uses: the uploaded
/// image when there is one, initials on the member's profile colour otherwise.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 36,
    this.showStatus = false,
    this.statusOverride,
  });

  final User? user;
  final double size;
  final bool showStatus;
  final UserStatus? statusOverride;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [_avatar(context), if (showStatus) _statusDot()],
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final decoration = BoxDecoration(
      color: user?.profileColor ?? fallbackProfileColor,
      shape: BoxShape.circle,
    );

    final initials = Text(
      user?.initials ?? '?',
      style: TextStyle(
        fontSize: size * 0.38,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );

    final url = fileUrl(ServerOrigin.maybeOf(context), user?.avatar);

    if (url == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: decoration,
        child: initials,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(child: initials),
      ),
    );
  }

  Widget _statusDot() {
    final status = statusOverride ?? user?.status ?? UserStatus.offline;

    final color = switch (status) {
      UserStatus.online => AppColors.online,
      UserStatus.idle => AppColors.idle,
      UserStatus.offline => AppColors.textFaint,
    };

    return Positioned(
      right: -1,
      bottom: -1,
      child: Container(
        width: size * 0.32,
        height: size * 0.32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
        ),
      ),
    );
  }
}

/// carries the server origin through the tree so an avatar deep in a message row
/// does not have to be handed the address by every ancestor.
class ServerOrigin extends InheritedWidget {
  const ServerOrigin({super.key, required this.baseUrl, required super.child});

  final String? baseUrl;

  static String? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServerOrigin>()?.baseUrl;

  @override
  bool updateShouldNotify(ServerOrigin oldWidget) =>
      oldWidget.baseUrl != baseUrl;
}

/// a file sent with a message: images get a thumbnail, everything else a card
/// with the name, and both open in the browser since there is no local viewer.
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.file, required this.onOpen});

  final ServerFile file;
  final void Function(ServerFile file) onOpen;

  static const double _maxHeight = 260;

  @override
  Widget build(BuildContext context) {
    final url = fileUrl(ServerOrigin.maybeOf(context), file);
    if (url == null) return const SizedBox.shrink();

    if (file.isImage) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: GestureDetector(
          onTap: () => onOpen(file),
          child: ClipRRect(
            borderRadius: AppRadius.medium,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _maxHeight,
                maxWidth: 380,
              ),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 120,
                        width: 200,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                errorBuilder: (_, _, _) =>
                    _fileCard(context, 'Image could not be loaded'),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: _fileCard(context, formatBytes(file.size)),
    );
  }

  Widget _fileCard(BuildContext context, String subtitle) {
    return InkWell(
      onTap: () => onOpen(file),
      borderRadius: AppRadius.medium,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: AppRadius.medium,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file_outlined,
              size: 18,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.originalName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
