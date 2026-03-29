
import 'dart:io';

import 'package:clean_guru/storageOptimizationScreen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class DuplicatesTab extends StatefulWidget {
  @override
  _DuplicatesTabState createState() => _DuplicatesTabState();
}

class _DuplicatesTabState extends State<DuplicatesTab> {
  List<List<File>> similarGroups = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _findSimilarImages();
  }


  Future<void> _findSimilarImages() async {
    try {
      // Request storage permission
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        setState(() => isLoading = false);
        return;
      }

      // Use more robust method to get media directories
      final directories = await getMediaDirectories();

      List<File> allImages = [];

      // Get all image files from accessible directories
      for (var dirPath in directories) {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final files = await dir.list(recursive: true).toList();
          allImages.addAll(
              files.whereType<File>().where((file) =>
                  ['.jpg', '.jpeg', '.png'].any(
                          (ext) => file.path.toLowerCase().endsWith(ext)
                  )
              )
          );
        }
      }

      // More advanced duplicate detection
      final detector = MediaDuplicateDetector();
      final duplicates = await detector.detectDuplicates(directories);

      setState(() {
        similarGroups = duplicates.map((media) =>
        [File(media.path), ...media.duplicates.map((dup) => File(dup.path))]
        ).toList();
        isLoading = false;
      });
    } catch (e) {
      print('Error finding similar images: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    if (similarGroups.isEmpty) {
      return Center(
        child: Text('No similar images found'),
      );
    }

    return ListView.builder(
      itemCount: similarGroups.length,
      padding: EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final group = similarGroups[index];
        return _buildSimilarGroup(group);
      },
    );
  }

  Widget _buildSimilarGroup(List<File> group) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '${group.length} Similar Images',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Row(
              children: group.map((file) => Container(
                width: 200,
                height: 200,
                margin: EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                  ),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

}