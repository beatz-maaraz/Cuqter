import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';

enum DroppedFileType { image, video, audio, document }

DroppedFileType getDroppedFileType(String nameOrPath) {
  final ext = nameOrPath.split('.').last.toLowerCase();
  if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext)) {
    return DroppedFileType.image;
  }
  if (['mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', '3gp'].contains(ext)) {
    return DroppedFileType.video;
  }
  if (['mp3', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'flac'].contains(ext)) {
    return DroppedFileType.audio;
  }
  return DroppedFileType.document;
}

String formatDroppedFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB'];
  var i = (bytes > 0) ? (bytes / 1024).floor().toString().length ~/ 3 : 0;
  if (i >= suffixes.length) i = suffixes.length - 1;
  double size = bytes / (1 << (10 * i));
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

/// A compact preview modal matching WhatsApp Desktop's attachment preview.
class DroppedFilesPreviewDialog extends StatefulWidget {
  final List<XFile> files;
  final String contactName;
  final void Function(List<XFile> files, String caption) onSend;

  const DroppedFilesPreviewDialog({
    super.key,
    required this.files,
    required this.contactName,
    required this.onSend,
  });

  @override
  State<DroppedFilesPreviewDialog> createState() =>
      _DroppedFilesPreviewDialogState();
}

class _DroppedFilesPreviewDialogState extends State<DroppedFilesPreviewDialog> {
  late List<XFile> _files;
  int _selectedIndex = 0;
  final TextEditingController _captionController = TextEditingController();
  final Map<String, Uint8List> _bytesCache = {};
  final Map<String, int> _sizeCache = {};
  bool _isLoadingCurrent = false;

  @override
  void initState() {
    super.initState();
    _files = List<XFile>.from(widget.files);
    _loadFileBytes(_selectedIndex);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _loadFileBytes(int index) async {
    if (index < 0 || index >= _files.length) return;
    final file = _files[index];
    if (_bytesCache.containsKey(file.path) && _sizeCache.containsKey(file.path)) {
      return;
    }

    if (mounted) setState(() => _isLoadingCurrent = true);
    try {
      final bytes = await file.readAsBytes();
      final len = await file.length();
      _bytesCache[file.path] = bytes;
      _sizeCache[file.path] = len;
    } catch (_) {}
    if (mounted) setState(() => _isLoadingCurrent = false);
  }

  void _onSelectFile(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
    });
    _loadFileBytes(index);
  }

  void _onRemoveFile(int index) {
    setState(() {
      _files.removeAt(index);
      if (_selectedIndex >= _files.length) {
        _selectedIndex = _files.length - 1;
      }
    });
    if (_files.isEmpty) {
      Navigator.pop(context);
    } else {
      _loadFileBytes(_selectedIndex);
    }
  }

  void _handleSend() {
    if (_files.isEmpty) return;
    final caption = _captionController.text.trim();
    Navigator.pop(context);
    widget.onSend(_files, caption);
  }

  @override
  Widget build(BuildContext context) {
    if (_files.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentFile = _files[_selectedIndex];
    final fileType = getDroppedFileType(currentFile.name);
    final fileSize = _sizeCache[currentFile.path] ?? 0;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: const Color(0xFF121212),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 540,
          maxHeight: 640,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF222222), width: 1),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send to ${widget.contactName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_files.length > 1)
                          Text(
                            '${_selectedIndex + 1} of ${_files.length} files',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_files.length > 1)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFE57373),
                        size: 22,
                      ),
                      tooltip: 'Remove this file',
                      onPressed: () => _onRemoveFile(_selectedIndex),
                    ),
                ],
              ),
            ),

            // Main Preview Area
            Expanded(
              child: Container(
                color: const Color(0xFF0D0D0D),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: _isLoadingCurrent
                    ? const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      )
                    : _buildMainPreview(currentFile, fileType, fileSize),
              ),
            ),

            // Thumbnail Carousel (if multiple files dropped)
            if (_files.length > 1)
              Container(
                height: 72,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                color: const Color(0xFF161616),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _files.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedIndex;
                    final file = _files[index];
                    final type = getDroppedFileType(file.name);
                    final bytes = _bytesCache[file.path];

                    return GestureDetector(
                      onTap: () => _onSelectFile(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFF242424),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? primaryColor : Colors.white12,
                            width: isSelected ? 2.5 : 1.0,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildThumbnailItem(file, type, bytes),
                      ),
                    );
                  },
                ),
              ),

            // Caption & Send Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: const Color(0xFF141414),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      decoration: InputDecoration(
                        hintText: 'Add a caption...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 13.5,
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF222222),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    color: primaryColor,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _handleSend,
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
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

  Widget _buildMainPreview(
    XFile file,
    DroppedFileType type,
    int sizeBytes,
  ) {
    switch (type) {
      case DroppedFileType.image:
        final bytes = _bytesCache[file.path];
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
            ),
          );
        }
        return const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );

      case DroppedFileType.video:
        return _buildFileCard(
          icon: Icons.videocam_rounded,
          iconColor: const Color(0xFFE57373),
          fileName: file.name,
          badgeText: 'VIDEO',
          sizeText: sizeBytes > 0 ? formatDroppedFileSize(sizeBytes) : '',
        );

      case DroppedFileType.audio:
        return _buildFileCard(
          icon: Icons.audiotrack_rounded,
          iconColor: const Color(0xFFFFB74D),
          fileName: file.name,
          badgeText: 'AUDIO',
          sizeText: sizeBytes > 0 ? formatDroppedFileSize(sizeBytes) : '',
        );

      case DroppedFileType.document:
        final isPdf = file.name.toLowerCase().endsWith('.pdf');
        return _buildFileCard(
          icon: isPdf
              ? Icons.picture_as_pdf_rounded
              : Icons.insert_drive_file_rounded,
          iconColor: isPdf ? const Color(0xFFEF5350) : const Color(0xFF64B5F6),
          fileName: file.name,
          badgeText: isPdf ? 'PDF' : 'DOC',
          sizeText: sizeBytes > 0 ? formatDroppedFileSize(sizeBytes) : '',
        );
    }
  }

  Widget _buildFileCard({
    required IconData icon,
    required Color iconColor,
    required String fileName,
    required String badgeText,
    required String sizeText,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 42,
                    color: iconColor,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: iconColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (sizeText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                sizeText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailItem(
    XFile file,
    DroppedFileType type,
    Uint8List? bytes,
  ) {
    if (type == DroppedFileType.image && bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
      );
    }

    IconData icon;
    Color iconColor;
    switch (type) {
      case DroppedFileType.image:
        icon = Icons.image_rounded;
        iconColor = Colors.purpleAccent;
        break;
      case DroppedFileType.video:
        icon = Icons.videocam_rounded;
        iconColor = const Color(0xFFE57373);
        break;
      case DroppedFileType.audio:
        icon = Icons.audiotrack_rounded;
        iconColor = const Color(0xFFFFB74D);
        break;
      case DroppedFileType.document:
        final isPdf = file.name.toLowerCase().endsWith('.pdf');
        icon = isPdf
            ? Icons.picture_as_pdf_rounded
            : Icons.insert_drive_file_rounded;
        iconColor = isPdf ? const Color(0xFFEF5350) : const Color(0xFF64B5F6);
        break;
    }

    return Center(
      child: Icon(
        icon,
        size: 24,
        color: iconColor,
      ),
    );
  }
}
