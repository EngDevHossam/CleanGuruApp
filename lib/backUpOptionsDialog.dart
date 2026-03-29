import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'contactCleanUp.dart';
import 'googleDriveBackup.dart';
import 'package:permission_handler/permission_handler.dart';


class BackupOptionsDialog {
  static Future<void> show(BuildContext context, {required List<DuplicateContact> duplicateContacts}) async {
    return showDialog(
      context: context,
      builder: (context) => BackupDialog(duplicateContacts: duplicateContacts),
    );
  }
}

class BackupDialog extends StatefulWidget {
  final List<DuplicateContact> duplicateContacts;

  const BackupDialog({Key? key, required this.duplicateContacts}) : super(key: key);

  @override
  _BackupDialogState createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  bool _backupInProgress = false;
  String _statusMessage = '';
  bool _backupCompleted = false;
  String _backupFilePath = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Backup Contacts'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where would you like to save your contacts backup?'),
          SizedBox(height: 16),
          if (_backupInProgress)
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Creating backup...'),
                ],
              ),
            )
          else if (_backupCompleted)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 32),
                  SizedBox(height: 8),
                  Text('Backup completed successfully!'),
                  SizedBox(height: 4),
                  Text(
                    'Saved to: $_backupFilePath',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
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
        if (!_backupInProgress && !_backupCompleted) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => _backupToLocalStorage(context),
            icon: Icon(Icons.save),
            label: Text('Local Storage'),
          ),
          ElevatedButton.icon(
            onPressed: () => _backupAndShare(context),
            icon: Icon(Icons.share),
            label: Text('Share File'),
          ),
        ] else if (_backupCompleted) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
          if (_backupFilePath.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _shareBackupFile(_backupFilePath),
              icon: Icon(Icons.share),
              label: Text('Share Backup'),
            ),
        ],
      ],
    );
  }

  Future<void> _backupToLocalStorage(BuildContext context) async {
    setState(() {
      _backupInProgress = true;
      _statusMessage = '';
    });

    try {
      // Request storage permission
      if (!await Permission.storage.request().isGranted) {
        setState(() {
          _backupInProgress = false;
          _statusMessage = 'Storage permission is required for backup';
        });
        return;
      }

      // Create backup file
      final backupFile = await _createBackupFile();

      setState(() {
        _backupInProgress = false;
        _backupCompleted = true;
        _backupFilePath = backupFile.path;
      });
    } catch (e) {
      setState(() {
        _backupInProgress = false;
        _statusMessage = 'Error creating backup: $e';
      });
    }
  }


  Future<void> _backupAndShare(BuildContext context) async {
    setState(() {
      _backupInProgress = true;
      _statusMessage = '';
    });

    try {
      // Create backup file
      final backupFile = await _createBackupFile();

      setState(() {
        _backupInProgress = false;
        _backupCompleted = true;
        _backupFilePath = backupFile.path;
      });

      // Share the backup file
      await _shareBackupFile(backupFile.path);
    } catch (e) {
      setState(() {
        _backupInProgress = false;
        _statusMessage = 'Error creating backup: $e';
      });
    }
  }

  Future<File> _createBackupFile() async {
    // Check if we already have contacts in the widget
    List<Contact> allContacts = [];

    if (widget.duplicateContacts.isNotEmpty) {
      // Extract all contacts from duplicate groups
      for (var dupGroup in widget.duplicateContacts) {
        allContacts.add(dupGroup.originalContact);
        allContacts.addAll(dupGroup.duplicates);
      }
    } else {
      // Get all contacts if the list is empty
      allContacts = await FlutterContacts.getContacts(withProperties: true);
    }

    // Convert contacts to JSON
    List<Map<String, dynamic>> contactsJson = [];
    for (var contact in allContacts) {
      contactsJson.add(contact.toJson());
    }

    // Create a backup file in the documents directory
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'contacts_backup_$timestamp.json';
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    // Write the JSON data to the file
    await file.writeAsString(jsonEncode(contactsJson));
    return file;
  }

  Future<void> _shareBackupFile(String filePath) async {
    try {
      final result = await Share.shareFiles(
        [filePath],
        text: 'Contacts Backup',
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'Error sharing backup: $e';
      });
    }
  }
}

class BackupOptionsSheet extends StatefulWidget {
  final List<DuplicateContact> duplicateContacts;

  const BackupOptionsSheet({
    Key? key,
    this.duplicateContacts = const []
  }) : super(key: key);

  @override
  State<BackupOptionsSheet> createState() => _BackupOptionsSheetState();
}



class _BackupOptionsSheetState extends State<BackupOptionsSheet> {
  String _lastBackupDate = 'Never';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLastBackupDate();
  }

  Future<void> _loadLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastBackupDate = prefs.getString('lastContactBackup') ?? 'Never';
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Drag handle at the top
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Close button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              // Scrollable content
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                  controller: controller,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Back up your contacts to Google Drive',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your contacts will be saved as a vCard file that you can restore later.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Last Backup: $_lastBackupDate',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Modified: Direct InkWell instead of _BackupOption widget
                        InkWell(
                          onTap: () async {
                            // First close the dialog
                            Navigator.pop(context);
                            // Then start the backup process
                            await _backupToGoogleDrive(context);
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.drive_folder_upload, color: Colors.blue),
                                SizedBox(width: 12),
                                Text(
                                  'Google Drive',
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Spacer(),
                                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _CancelButton(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _backupToGoogleDrive(BuildContext context) async {
    // Reference to the dialog context
    BuildContext? dialogContext;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          // Store the dialog context for later dismissal
          dialogContext = context;
          return AlertDialog(
            title: const Text('Preparing Backup'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Creating contacts backup...'),
              ],
            ),
          );
        },
      );

      // Add a safety timeout to close the dialog if something goes wrong
      Future.delayed(const Duration(seconds: 30), () {
        if (dialogContext != null && Navigator.of(dialogContext!, rootNavigator: true).canPop()) {
          Navigator.of(dialogContext!, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup operation timed out. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });

      print("Starting contact backup process");

      // Create a temporary file with all contacts data in vCard format
      final backupFile = await _createContactsBackupFile();
      if (backupFile == null) {
        print("Failed to create backup file");
        throw Exception('Failed to create backup file');
      }

      print("Backup file created: ${backupFile.path}");
      print("File size: ${await backupFile.length()} bytes");

      // Initialize Google Drive backup
      final googleDriveBackup = GoogleDriveBackup();

      print("Starting Google Drive authentication");

      // Perform backup
      await googleDriveBackup.backupContacts(backupFile);

      print("Backup to Google Drive completed");

      // Save the backup date
      await _saveLastBackupDate();

      print("Last backup date saved");

      // Close the dialog - with null check
      if (dialogContext != null && Navigator.of(dialogContext!, rootNavigator: true).canPop()) {
        Navigator.of(dialogContext!, rootNavigator: true).pop();
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contacts backed up to Google Drive successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stack) {
      // Log the full error and stack trace
      print('Error in backup function: $e');
      print('Stack trace: $stack');

      // Ensure dialog is closed in case of error
      if (dialogContext != null && Navigator.of(dialogContext!, rootNavigator: true).canPop()) {
        Navigator.of(dialogContext!, rootNavigator: true).pop();
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error backing up contacts: ${e.toString().length > 100 ? e.toString().substring(0, 100) + '...' : e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }



  static Future<io.File?> _createContactsBackupFile() async {
    try {
      // Request contact permissions
      if (!await FlutterContacts.requestPermission()) {
        throw Exception('Contacts permission required');
      }

      // Get all contacts with full info
      final contacts = await FlutterContacts.getContacts(withProperties: true);

      // Get temporary directory
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/contacts_backup_${DateTime.now().millisecondsSinceEpoch}.vcf';
      final file = io.File(filePath);

      // Create vCard content
      final vCardContent = StringBuffer();
      for (var contact in contacts) {
        vCardContent.writeln('BEGIN:VCARD');
        vCardContent.writeln('VERSION:3.0');

        // Name
        if (contact.displayName.isNotEmpty) {
          vCardContent.writeln('FN:${contact.displayName}');
        }

        // Phone numbers
        for (var phone in contact.phones) {
          vCardContent.writeln('TEL;TYPE=${phone.label ?? "CELL"}:${phone.number}');
        }

        // Emails
        for (var email in contact.emails) {
          vCardContent.writeln('EMAIL;TYPE=${email.label ?? "HOME"}:${email.address}');
        }

        // End of vCard
        vCardContent.writeln('END:VCARD');
      }

      // Write to file
      await file.writeAsString(vCardContent.toString());
      return file;
    } catch (e) {
      print('Error creating contacts backup file: $e');
      return null;
    }
  }

  static Future<void> _saveLastBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final formatted = DateFormat('MMM d, yyyy h:mm a').format(now);
    await prefs.setString('lastContactBackup', formatted);
  }
}

class _BackupOption extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _BackupOption({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue),
            SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}