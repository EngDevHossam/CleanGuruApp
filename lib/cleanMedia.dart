import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';


class MediaCleanupTab extends StatefulWidget {
  @override
  _MediaCleanupTabState createState() => _MediaCleanupTabState();
}

class _MediaCleanupTabState extends State<MediaCleanupTab> {
  MediaType _selectedType = MediaType.photos;
  List<MediaFile> _mediaFiles = [];
  bool _isLoading = false;
  bool _hasSelectedItems = false;

  @override
  void initState() {
    super.initState();
    _loadMediaFiles();
  }

  Future<void> _loadMediaFiles() async {
    setState(() => _isLoading = true);
    try {
      // Existing permission request logic
      final directories = await _getMediaDirectories();
      List<MediaFile> allFiles = []; // Collect ALL media files first

      for (var dir in directories) {
        try {
          final directory = Directory(dir);
          if (await directory.exists()) {
            await for (var entity in directory.list(recursive: true)) {
              if (entity is File && _isMediaFile(entity.path)) {
                final stat = await entity.stat();

                // Add all media files to the list
                allFiles.add(MediaFile(
                  name: entity.path.split('/').last,
                  path: entity.path,
                  size: stat.size,
                  lastModified: stat.modified,
                  isSelected: false,
                  type: _getMediaType(entity.path),
                ));
              }
            }
          }
        } catch (e) {
          print('Error scanning directory $dir: $e');
        }
      }

      // Now filter by the selected media type
      final filteredFiles = allFiles.where((file) => file.type == _selectedType).toList();

      // Print some debug info
      print('Found ${allFiles.length} total media files');
      print('Photos: ${allFiles.where((f) => f.type == MediaType.photos).length}');
      print('Videos: ${allFiles.where((f) => f.type == MediaType.videos).length}');
      print('Audio: ${allFiles.where((f) => f.type == MediaType.audio).length}');
      print('Filtered to ${filteredFiles.length} ${_selectedType.name} files');

      setState(() {
        _mediaFiles = filteredFiles;
        _isLoading = false;
        _hasSelectedItems = false;
      });
    } catch (e) {
      print('Error loading media files: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<String>> _getMediaDirectories() async {
    List<String> directories = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Recordings',  // Added for audio recordings
      '/storage/emulated/0/Sounds',      // Added for audio files
      '/storage/emulated/0/Audio',       // Added for audio files// Added for podcasts
      '/storage/emulated/0/Ringtones',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Podcasts',
      '/storage/emulated/0/Notifications',
      '/storage/emulated/0/Audiobooks',
      '/storage/emulated/0/WhatsApp/Media/WhatsApp Audio',// Added for ringtones
    ];

    try {
      final storageDir = await getExternalStorageDirectory();
      if (storageDir != null) {
        directories.add(storageDir.path);
      }
    } catch (e) {
      print('Error getting external storage directory: $e');
    }

    // Filter out directories that don't exist
    List<String> existingDirectories = [];
    for (var dir in directories) {
      try {
        if (await Directory(dir).exists()) {
          existingDirectories.add(dir);
          print('Added directory: $dir');
        }
      } catch (e) {
        print('Error checking directory $dir: $e');
      }
    }

    return existingDirectories;
  }

  // Also add these helper methods if they're not already defined
  bool _isMediaFile(String path) {
    final ext = path.toLowerCase();
    // Expanded list of audio file extensions
    return ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png') || ext.endsWith('.gif') ||  // Photos
        ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi') || ext.endsWith('.mkv') ||  // Videos
        // Expanded Audio Extensions
        ext.endsWith('.mp3') ||
        ext.endsWith('.wav') ||
        ext.endsWith('.m4a') ||
        ext.endsWith('.aac') ||
        ext.endsWith('.ogg') ||
        ext.endsWith('.flac') ||
        ext.endsWith('.opus') ||
        ext.endsWith('.wma') ||
        ext.endsWith('.alac') ||  // Apple Lossless Audio Codec
        ext.endsWith('.webm') ||  // WebM audio
        ext.endsWith('.mpeg') ||  // MPEG audio
        ext.endsWith('.aiff') ||  // Audio Interchange File Format
        ext.endsWith('.mid') ||   // MIDI files
        ext.endsWith('.amr') ||   // Adaptive Multi-Rate audio codec
        ext.endsWith('.ac3') ||   // Audio Codec 3
        ext.endsWith('.ra') ||    // RealAudio
        ext.endsWith('.ram');     // RealAudio Metadata
  }



  MediaType _getMediaType(String path) {
    final ext = path.toLowerCase();
    if (ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png') || ext.endsWith('.gif')) {
      return MediaType.photos;
    } else if (ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi') || ext.endsWith('.mkv')) {
      return MediaType.videos;
    } else if (
    ext.endsWith('.mp3') ||
        ext.endsWith('.wav') ||
        ext.endsWith('.m4a') ||
        ext.endsWith('.aac') ||
        ext.endsWith('.ogg') ||
        ext.endsWith('.flac') ||
        ext.endsWith('.opus') ||
        ext.endsWith('.wma') ||
        ext.endsWith('.alac') ||
        ext.endsWith('.webm') ||
        ext.endsWith('.mpeg') ||
        ext.endsWith('.aiff') ||
        ext.endsWith('.mid') ||
        ext.endsWith('.amr') ||
        ext.endsWith('.ac3') ||
        ext.endsWith('.ra') ||
        ext.endsWith('.ram')
    ) {
      return MediaType.audio;
    }
    // Default fallback
    return MediaType.photos;
  }

  void _checkSelectedItems() {
    setState(() {
      _hasSelectedItems = _mediaFiles.any((file) => file.isSelected);
    });
  }


  void _toggleMediaType(MediaType type) {
    if (_selectedType != type) {
      setState(() {
        _selectedType = type;
        _loadMediaFiles();
      });
    }
  }

  void _toggleAllSelection(bool selected) {
    setState(() {
      for (var file in _mediaFiles) {
        file.isSelected = selected;
      }
      _hasSelectedItems = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Media type selector
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMediaTypeCard(
                  icon: Icons.photo_outlined,
                  label: 'Photos',
                  type: MediaType.photos,
                ),
                _buildMediaTypeCard(
                  icon: Icons.videocam_outlined,
                  label: 'Videos',
                  type: MediaType.videos,
                ),
                _buildMediaTypeCard(
                  icon: Icons.audiotrack_outlined,
                  label: 'Audio',
                  type: MediaType.audio,
                ),
              ],
            ),
          ),

          // Selection header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_mediaFiles.where((file) => file.isSelected).length} ${_selectedType.name} selected',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                // Replace this TextButton with a Row containing both buttons
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _toggleAllSelection(true),
                      child: Text(
                        'Select All',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _toggleAllSelection(false),
                      child: Text(
                        'Deselect All',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Media list with stacked delete button
          Expanded(
            child: Stack(
              children: [
                // Media list
                _buildMediaList(),

                // Delete button at the bottom when items are selected
                if (_hasSelectedItems)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.white,
                      padding: EdgeInsets.all(16),
                      child: ElevatedButton.icon(
                        onPressed: _deleteSelectedFiles,
                        icon: Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Delete ${_mediaFiles.where((file) => file.isSelected).length} Items',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          minimumSize: Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelectedFiles() async {
    // Get selected files count for messages
    final selectedFiles = _mediaFiles.where((file) => file.isSelected).toList();
    final selectedCount = selectedFiles.length;

    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No files selected')),
      );
      return;
    }

    // Calculate total size that will be freed
    final totalSize = selectedFiles.fold(0, (sum, file) => sum + file.size);

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selectedType.name}'),
        content: Text(
          'Are you sure you want to delete $selectedCount ${_selectedType.name}?\n'
              'This will free up ${_formatFileSize(totalSize)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Deleting files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Deleting $selectedCount ${_selectedType.name}...'),
          ],
        ),
      ),
    );

    // Delete the files
    int deletedCount = 0;
    try {
      for (var file in selectedFiles) {
        final fileToDelete = File(file.path);
        if (await fileToDelete.exists()) {
          await fileToDelete.delete();
          deletedCount++;
        }
      }

      // Dismiss the progress dialog
      Navigator.of(context).pop();

      // Remove deleted files from the list
      setState(() {
        _mediaFiles.removeWhere((file) => file.isSelected);
        _hasSelectedItems = false;
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully deleted $deletedCount ${_selectedType.name}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Dismiss the progress dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error deleting files: $e');

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting files: $e'),
          backgroundColor: Colors.red,
        ),
      );

      // Refresh the list to show the current state
      _loadMediaFiles();
    }
  }

  Widget _buildMediaTypeCard({
    required IconData icon,
    required String label,
    required MediaType type
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () => _toggleMediaType(type),
      child: Container(
        width: 100,
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.blue.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected ? Colors.blue : Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaList() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_mediaFiles.isEmpty) {
      return Center(
        child: Text(
          'No ${_selectedType.name} found',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: _mediaFiles.length,
      separatorBuilder: (context, index) => SizedBox(height: 12),
      itemBuilder: (context, index) => _buildMediaListItem(_mediaFiles[index]),
    );
  }

  Widget _buildMediaListItem(MediaFile file) {
    return GestureDetector(
      onTap: () {
        setState(() {
          file.isSelected = !file.isSelected;
          _checkSelectedItems();
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              child: Container(
                width: 80,
                height: 80,
                color: Colors.grey[200],
                child: file.type == MediaType.audio
                    ? Icon(Icons.audiotrack, color: Colors.grey[400], size: 32)
                    : Image.file(
                  File(file.path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    file.type == MediaType.videos
                        ? Icons.videocam
                        : Icons.image,
                    color: Colors.grey[400],
                    size: 32,
                  ),
                ),
              ),
            ),

            // File details
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Taken ${DateFormat('dd/MM/yyyy').format(file.lastModified)}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    if (file.type == MediaType.videos || file.type == MediaType.audio)
                      Text(
                        'Duration 03:40',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // File size and checkbox
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatFileSize(file.size),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 8),
                  Transform.scale(
                    scale: 1.2,
                    child: Checkbox(
                      value: file.isSelected,
                      onChanged: (value) {
                        setState(() {
                          file.isSelected = value ?? false;
                          _checkSelectedItems();
                        });
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      activeColor: Colors.blue,
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

}

enum MediaType {
  photos,
  videos,
  audio,
}


class MediaFile {
  final String name;
  final String path;
  final int size;
  final DateTime lastModified;
  final MediaType type;
  bool isSelected;

  MediaFile({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
    required this.type,
    this.isSelected = true,
  });
}