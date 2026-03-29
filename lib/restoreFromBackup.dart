

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';


// RestoreContactsDialog implementation
class RestoreContactsDialog {
  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => RestoreDialog(),
    );
  }
}

class RestoreDialog extends StatefulWidget {
  const RestoreDialog({Key? key}) : super(key: key);

  @override
  _RestoreDialogState createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<RestoreDialog> {
  bool _restoreInProgress = false;
  String _statusMessage = '';
  bool _restoreCompleted = false;
  String _selectedFilePath = '';
  String _selectedFileName = '';
  int _contactsCount = 0;

  @override
  void initState() {
    super.initState();
    _checkForBackupFiles();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Restore Contacts'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select a backup file to restore your contacts:'),
          SizedBox(height: 16),
          if (_restoreInProgress)
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Restoring contacts...'),
                ],
              ),
            )
          else if (_restoreCompleted)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 32),
                  SizedBox(height: 8),
                  Text('Restored $_contactsCount contacts successfully!'),
                ],
              ),
            )
          else if (_selectedFilePath.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected file:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(_selectedFileName),
                  ],
                ),
              )
            else if (_statusMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.red),
                  ),
                ),
        ],
      ),
      actions: [
        if (!_restoreInProgress && !_restoreCompleted) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _selectBackupFile,
            icon: Icon(Icons.folder_open),
            label: Text('Select Backup'),
          ),
          if (_selectedFilePath.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _restoreContacts,
              icon: Icon(Icons.restore),
              label: Text('Restore'),
            ),
        ] else if (_restoreCompleted) ...[
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done'),
          ),
        ],
      ],
    );
  }

  Future<void> _checkForBackupFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dir = Directory(directory.path);
      final List<FileSystemEntity> entities = await dir.list().toList();
      final backupFiles = entities.whereType<File>().where(
              (file) => file.path.contains('contacts_backup') && file.path.endsWith('.json')
      ).toList();

      if (backupFiles.isEmpty) {
        setState(() {
          _statusMessage = 'No local backup files found. You can select a backup file from device storage.';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error checking for backup files: $e';
      });
    }
  }

  Future<void> _selectBackupFile() async {
    try {
      // Request appropriate permissions based on platform
      if (Platform.isAndroid) {
        // For Android 13+ (API 33+), we need more specific permissions
        var status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }

        // If photos permission is not available or granted, fall back to storage
        if (!status.isGranted) {
          status = await Permission.storage.status;
          if (!status.isGranted) {
            status = await Permission.storage.request();
          }
        }

        // If still not granted, try manage external storage (for Android 11+)
        if (!status.isGranted) {
          try {
            status = await Permission.manageExternalStorage.request();
          } catch (e) {
            print("Error requesting manage external storage: $e");
          }

          if (!status.isGranted) {
            setState(() {
              _statusMessage = 'Storage permission is required to select a file';
            });
            return;
          }
        }
      }

      // Show available local backups first if any exist
      final directory = await getApplicationDocumentsDirectory();
      final dir = Directory(directory.path);
      final List<FileSystemEntity> entities = await dir.list().toList();
      final backupFiles = entities.whereType<File>()
          .where((file) => file.path.contains('contacts_backup') && file.path.endsWith('.json'))
          .toList();

      if (backupFiles.isNotEmpty) {
        // Sort by modification time (newest first)
        backupFiles.sort((a, b) {
          final statA = a.statSync();
          final statB = b.statSync();
          return statB.modified.compareTo(statA.modified);
        });

        // Show a dialog to choose from local backups
        final selectedFile = await showDialog<File>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Select Backup File'),
            content: Container(
              width: double.maxFinite,
              height: 300,
              child: ListView.builder(
                itemCount: backupFiles.length,
                itemBuilder: (context, index) {
                  final file = backupFiles[index];
                  final fileName = file.path.split('/').last;
                  final stats = file.statSync();

                  return ListTile(
                    title: Text(fileName),
                    subtitle: Text(
                      'Modified: ${DateFormat('MMM d, yyyy HH:mm').format(stats.modified)}',
                    ),
                    onTap: () => Navigator.of(context).pop(file),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();

                  // Use file picker to select a file from elsewhere
                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['json'],
                  );

                  if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
                    setState(() {
                      _selectedFilePath = result.files.single.path!;
                      _selectedFileName = result.files.single.name;
                      _statusMessage = '';
                    });

                    // Trigger contacts restoration
                    await _restoreContacts();
                  }
                },
                child: Text('Browse Device'),
              ),
            ],
          ),
        );

        if (selectedFile != null) {
          setState(() {
            _selectedFilePath = selectedFile.path;
            _selectedFileName = selectedFile.path.split('/').last;
            _statusMessage = '';
          });

          // Trigger contacts restoration for local backup
          await _restoreContacts();
          return;
        }
      }

      // If no local backups or user wants to browse, use file picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path!;
          _selectedFileName = result.files.single.name;
          _statusMessage = '';
        });

        // Trigger contacts restoration
        await _restoreContacts();
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error selecting file: $e';
      });
    }
  }


  Future<void> _restoreContacts() async {
    // 1. Initial validation: Check if a file is selected
    if (_selectedFilePath.isEmpty) {
      setState(() {
        _statusMessage = 'Please select a backup file first';
      });
      return;
    }

    // 2. Set UI to restoration in progress state
    setState(() {
      _restoreInProgress = true;
      _statusMessage = '';
    });

    try {
      // 3. Request contacts permission
      if (!await FlutterContacts.requestPermission(readonly: false)) {
        setState(() {
          _restoreInProgress = false;
          _statusMessage = 'Contacts permission is required for restoration';
        });
        return;
      }

      // 4. Read the backup file
      final file = File(_selectedFilePath);

      // Check if file exists
      if (!await file.exists()) {
        setState(() {
          _restoreInProgress = false;
          _statusMessage = 'Backup file not found';
        });
        return;
      }

      // 5. Read file contents
      final jsonString = await file.readAsString();

      // Validate JSON content
      if (jsonString.isEmpty) {
        setState(() {
          _restoreInProgress = false;
          _statusMessage = 'Backup file is empty';
        });
        return;
      }

      // 6. Parse JSON
      final List<dynamic> contactsJson = jsonDecode(jsonString);

      // 7. Show confirmation dialog
      final shouldRestore = await _showConfirmationDialog(contactsJson.length);

      if (!shouldRestore) {
        setState(() {
          _restoreInProgress = false;
        });
        return;
      }

      // 8. Create and insert contacts
      int restoredCount = 0;
      int skippedCount = 0;

      for (var contactJson in contactsJson) {
        try {
          // Convert JSON to Contact object
          final contact = Contact.fromJson(contactJson);

          // Check if contact already exists
          bool isDuplicate = await _checkIfContactExists(contact);

          if (!isDuplicate) {
            // Insert contact if not a duplicate
            await contact.insert();
            restoredCount++;
          } else {
            skippedCount++;
          }
        } catch (e) {
          // Log individual contact restoration errors
          print('Error restoring individual contact: $e');
        }
      }

      // 9. Update UI with restoration results
      setState(() {
        _restoreInProgress = false;
        _restoreCompleted = true;
        _contactsCount = restoredCount;
      });

      // 10. Show summary dialog
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Restore Complete'),
          content: Text(
            'Restored $restoredCount contacts\n'
                'Skipped $skippedCount duplicate contacts',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );

    } catch (e) {
      // 11. Handle any unexpected errors
      setState(() {
        _restoreInProgress = false;
        _statusMessage = 'Error restoring contacts: ${e.toString()}';
      });

      // Optional: Show error dialog
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Restoration Error'),
          content: Text('An unexpected error occurred: ${e.toString()}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<bool> _checkIfContactExists(Contact contact) async {
    // Get all existing contacts
    final existingContacts = await FlutterContacts.getContacts(
      withProperties: true,
      withThumbnail: false,
    );

    // Check if this contact already exists (by name and first phone number)
    for (var existing in existingContacts) {
      if (existing.displayName == contact.displayName) {
        // If both have phones, check if any phone numbers match
        if (existing.phones.isNotEmpty && contact.phones.isNotEmpty) {
          for (var phone in existing.phones) {
            for (var newPhone in contact.phones) {
              if (_arePhonesSimilar(phone.number, newPhone.number)) {
                return true; // This contact already exists
              }
            }
          }
        }
      }
    }

    return false;
  }

  bool _arePhonesSimilar(String phone1, String phone2) {
    // Normalize phone numbers for comparison
    final normalized1 = _normalizePhone(phone1);
    final normalized2 = _normalizePhone(phone2);

    // Compare the last 9 digits (to handle different country codes)
    if (normalized1.length >= 9 && normalized2.length >= 9) {
      final end1 = normalized1.substring(normalized1.length - 9);
      final end2 = normalized2.substring(normalized2.length - 9);
      return end1 == end2;
    }

    // If numbers are shorter, compare them directly
    return normalized1 == normalized2;
  }

  String _normalizePhone(String phone) {
    // Remove all non-digit characters
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  Future<bool> _showConfirmationDialog(int contactCount) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Restore'),
        content: Text(
            'This will restore $contactCount contacts from the backup. '
                'Duplicate contacts will be skipped.\n\n'
                'Do you want to continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Restore'),
          ),
        ],
      ),
    ) ?? false;
  }
}

// BackupContactsFunction for the ContactCleanupTab to use
Future<void> backupContacts(BuildContext context) async {
  try {
    // Request contacts permission first
    if (!await FlutterContacts.requestPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contact permission is required for backup'))
      );
      return;
    }

    // Get all contacts with properties and photos
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: true,
    );

    // Convert contacts to JSON
    List<Map<String, dynamic>> contactsJson = [];
    for (var contact in contacts) {
      contactsJson.add(contact.toJson());
    }

    // Create backup file
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'contacts_backup_$timestamp.json';
    final backupFile = File('${directory.path}/$fileName');

    // Write contacts to file
    await backupFile.writeAsString(jsonEncode(contactsJson));

    // Show dialog to choose backup method
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup Created'),
        content: Text('${contacts.length} contacts backed up successfully.\n\nBackup saved to app storage as:\n$fileName'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Keep in App'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // Share the file to save elsewhere
              await Share.shareFiles(
                [backupFile.path],
                text: 'Contact Backup (${contacts.length} contacts)',
              );
            },
            child: const Text('Save to Device'),
          ),
        ],
      ),
    );

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Backup completed successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error during backup: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}


Future<void> restoreContactsDirectly(BuildContext context) async {
  try {
    // Try to look in Downloads folder first
    final downloadPath = await _getDownloadsPath();
    List<File> backupFiles = [];

    if (downloadPath != null) {
      final downloadsDir = Directory(downloadPath);
      if (await downloadsDir.exists()) {
        final entities = await downloadsDir.list().toList();
        backupFiles = entities
            .whereType<File>()
            .where((file) =>
        file.path.contains('contacts_backup') &&
            file.path.endsWith('.json')
        )
            .toList();

        // Sort by modification time (newest first), limiting to last 5 files
        backupFiles.sort((a, b) {
          final statA = a.statSync();
          final statB = b.statSync();
          return statB.modified.compareTo(statA.modified);
        });
        backupFiles = backupFiles.take(5).toList();
      }
    }

    // If no recent backup files found, immediately open file picker
    if (backupFiles.isEmpty) {
      await _openFilePicker(context);
      return;
    }

    // Immediately restore the most recent backup file
    if (backupFiles.isNotEmpty) {
      final mostRecentFile = backupFiles.first;
      await _restoreFromFile(context, mostRecentFile);
      return;
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error accessing backup files: $e')),
    );
    // Fallback to file picker if there's any error
    await _openFilePicker(context);
  }
}

Future<String?> _getDownloadsPath() async {
  // For Android
  if (Platform.isAndroid) {
    // Request storage permission
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        return null;
      }
    }

    try {
      // Try to access the standard Downloads directory
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        return downloadsDir.path;
      }

      // Fallback to external storage directory
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return externalDir.path;
      }
    } catch (e) {
      print('Error accessing Downloads directory: $e');
    }
  }

  // For iOS (doesn't typically use Downloads folder)
  if (Platform.isIOS) {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  return null;
}
// Helper to open file picker
Future<void> _openFilePicker(BuildContext context) async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );

  if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
    _restoreFromFile(context, File(result.files.single.path!));
  }
}

// Helper to restore from a specific file
Future<void> _restoreFromFile(BuildContext context, File file) async {
  final filePath = file.path;
  final fileName = file.path.split('/').last;

  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Restoring Contacts'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Please wait...'),
        ],
      ),
    ),
  );

  try {
    // Request contacts permission
    if (!await FlutterContacts.requestPermission(readonly: false)) {
      Navigator.of(context).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contacts permission required')),
      );
      return;
    }

    if (!await file.exists()) {
      Navigator.of(context).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup file not found')),
      );
      return;
    }

    // Read file contents
    final jsonString = await file.readAsString();

    // Validate JSON content
    if (jsonString.isEmpty) {
      Navigator.of(context).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup file is empty')),
      );
      return;
    }

    // Parse JSON
    final List<dynamic> contactsJson = jsonDecode(jsonString);

    // Create and insert contacts
    int restoredCount = 0;
    int skippedCount = 0;

    for (var contactJson in contactsJson) {
      try {
        // Convert JSON to Contact object
        final contact = Contact.fromJson(contactJson);

        // Check if contact already exists
        bool isDuplicate = await _checkIfContactExists(contact);

        if (!isDuplicate) {
          // Insert contact if not a duplicate
          await contact.insert();
          restoredCount++;
        } else {
          skippedCount++;
        }
      } catch (e) {
        print('Error restoring contact: $e');
      }
    }

    // Dismiss loading dialog
    Navigator.of(context).pop();

    // Show completion dialog with share option
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore Complete'),
        content: Text(
            'Restored $restoredCount contacts\nSkipped $skippedCount duplicate contacts'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done'),
          ),
          ElevatedButton.icon(
            icon: Icon(Icons.share),
            label: Text('Share Backup File'),
            onPressed: () async {
              Navigator.of(context).pop();

              // Share the backup file
              await Share.shareFiles(
                [filePath],
                text: 'Contact backup file ($fileName)',
              );
            },
          ),
        ],
      ),
    );

  } catch (e) {
    // Dismiss loading dialog if still showing
    Navigator.of(context, rootNavigator: true).pop();

    // Show error
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error restoring contacts: $e')),
    );
  }
}


Future<bool> _checkIfContactExists(Contact contact) async {
  // Get all existing contacts
  final existingContacts = await FlutterContacts.getContacts(
    withProperties: true,
    withThumbnail: false,
  );

  // Check if this contact already exists (by name and first phone number)
  for (var existing in existingContacts) {
    if (existing.displayName == contact.displayName) {
      // If both have phones, check if any phone numbers match
      if (existing.phones.isNotEmpty && contact.phones.isNotEmpty) {
        for (var phone in existing.phones) {
          for (var newPhone in contact.phones) {
            if (_arePhonesSimilar(phone.number, newPhone.number)) {
              return true; // This contact already exists
            }
          }
        }
      }
    }
  }

  return false;
}

bool _arePhonesSimilar(String phone1, String phone2) {
  // Normalize phone numbers for comparison
  final normalized1 = _normalizePhone(phone1);
  final normalized2 = _normalizePhone(phone2);

  // Compare the last 9 digits (to handle different country codes)
  if (normalized1.length >= 9 && normalized2.length >= 9) {
    final end1 = normalized1.substring(normalized1.length - 9);
    final end2 = normalized2.substring(normalized2.length - 9);
    return end1 == end2;
  }

  // If numbers are shorter, compare them directly
  return normalized1 == normalized2;
}

String _normalizePhone(String phone) {
  // Remove all non-digit characters
  return phone.replaceAll(RegExp(r'[^\d]'), '');
}