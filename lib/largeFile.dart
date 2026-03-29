

class LargeFile {
  final String path;
  final int size;
  final bool isFolder;
  bool isSelected;

  LargeFile({
    required this.path,
    required this.size,
    required this.isFolder,
    this.isSelected = true,
  });
}