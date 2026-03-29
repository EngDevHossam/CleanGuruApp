
import 'dart:convert';
import 'dart:io';

import 'package:clean_guru/restoreFromBackup.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/contact.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math' as math;
import 'backUpOptionsDialog.dart';
import 'restoreFromBackup.dart';



class ContactCleanupTab extends StatefulWidget {
  const ContactCleanupTab({Key? key}) : super(key: key);

  @override
  State<ContactCleanupTab> createState() => _ContactCleanupTabState();
}

class _ContactCleanupTabState extends State<ContactCleanupTab> {
  List<DuplicateContact> _duplicateContacts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        throw Exception('Contacts permission required');
      }

      // Get all contacts with full info
      final contacts = await FlutterContacts.getContacts(withProperties: true);

      // Find duplicates by name
      final Map<String, List<Contact>> nameGroups = {};
      for (var contact in contacts) {
        final normalizedName = _normalizeName(contact.displayName).toLowerCase();
        if (normalizedName.isNotEmpty) {
          nameGroups.putIfAbsent(normalizedName, () => []).add(contact);
        }
      }

      // Create list of duplicate contacts
      final duplicates = <DuplicateContact>[];

      // Process groups with duplicates
      for (var entry in nameGroups.entries) {
        if (entry.value.length > 1) {  // If there's more than one contact with this name
          final originalContact = entry.value.first;
          final duplicateContacts = entry.value.skip(1).toList();

          duplicates.add(DuplicateContact(
            originalContact: originalContact,
            duplicates: duplicateContacts,
            isSelected: true,
          ));
        }
      }

      print('Total contacts found: ${contacts.length}');
      print('Duplicate groups found: ${duplicates.length}');
      for (var dup in duplicates) {
        print('Original: ${dup.originalContact.displayName} - ${dup.originalContact.phones.map((p) => p.number).join(", ")}');
        for (var d in dup.duplicates) {
          print('Duplicate: ${d.displayName} - ${d.phones.map((p) => p.number).join(", ")}');
        }
      }

      setState(() {
        _duplicateContacts = duplicates;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading contacts: $e');
      setState(() => _isLoading = false);
    }
  }

  String _normalizeName(String name) {
    // Remove spaces, special characters, and make lowercase
    return name.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }


  Future<void> _mergeSelectedContacts() async {
    try {
      // Ensure we have write permissions
      if (!await FlutterContacts.requestPermission(readonly: false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contacts permission is required')),
        );
        return;
      }

      // Check if any duplicates are selected
      final selectedDuplicates = _duplicateContacts.where((item) => item.isSelected).toList();
      print("Selected duplicates: ${selectedDuplicates.length}");

      if (selectedDuplicates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No contacts selected for merging')),
        );
        return;
      }

      setState(() => _isLoading = true);

      // Confirm the merge operation
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Merge Contacts'),
          content: Text('Are you sure you want to merge ${selectedDuplicates.length} contact groups? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Merge'),
            ),
          ],
        ),
      ) ?? false;

      if (!confirmed) {
        setState(() => _isLoading = false);
        return;
      }

      print("Starting merge process for ${selectedDuplicates.length} groups");
      int successCount = 0;
      int failureCount = 0;

      // Process each selected duplicate group
      for (var duplicateGroup in selectedDuplicates) {
        try {
          print("Processing group: ${duplicateGroup.originalContact.displayName}");
          print("Original ID: ${duplicateGroup.originalContact.id}");
          print("Number of duplicates: ${duplicateGroup.duplicates.length}");

          // Get the original and duplicate contacts
          final originalContact = duplicateGroup.originalContact;
          final duplicates = duplicateGroup.duplicates;

          // Create a merged contact based on the original
          final mergedContact = originalContact.toJson();

          // Merge in properties from duplicates
          for (var duplicate in duplicates) {
            // Merge phone numbers
            for (var phone in duplicate.phones) {
              final phoneJson = phone.toJson();
              bool isDuplicate = originalContact.phones.any(
                      (p) => _arePhonesSimilar(p.number, phone.number)
              );

              if (!isDuplicate) {
                (mergedContact['phones'] as List).add(phoneJson);
              }
            }

            // Merge emails
            for (var email in duplicate.emails) {
              final emailJson = email.toJson();
              bool isDuplicate = originalContact.emails.any(
                      (e) => e.address.toLowerCase() == email.address.toLowerCase()
              );

              if (!isDuplicate) {
                (mergedContact['emails'] as List).add(emailJson);
              }
            }

            // Merge addresses
            for (var address in duplicate.addresses) {
              final addressJson = address.toJson();
              bool isDuplicate = originalContact.addresses.any(
                      (a) => a.address == address.address
              );

              if (!isDuplicate) {
                (mergedContact['addresses'] as List).add(addressJson);
              }
            }
          }

          // Create a new contact from the merged data
          final contact = Contact.fromJson(mergedContact);

          try {
            // Try to update the original contact
            await contact.update();

            // Delete the duplicates
            for (var duplicate in duplicates) {
              await duplicate.delete();
            }

            successCount++;
          } catch (updateError) {
            // If update fails, try alternative merge
            try {
              await _alternativeMergeContacts(originalContact, duplicates);
              successCount++;
            } catch (alternativeError) {
              print('Alternative merge failed: $alternativeError');
              failureCount++;
            }
          }
        } catch (e) {
          print('Error processing contact group: $e');
          failureCount++;
        }
      }

      // Reload contacts to reflect changes
      await _loadContacts();

      // Show summary of merge operation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Merge completed. $successCount successful, $failureCount failed.'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      print('Critical error in merge function: $e');
      print('Stack trace: $stackTrace');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error during merge: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Alternative merge approach
  Future<void> _alternativeMergeContacts(Contact originalContact, List<Contact> duplicates) async {
    print("Using alternative merge approach");

    // Step 1: Create a completely new contact with all merged information
    final newContact = Contact();

    // Copy basic info from original
    newContact.name = originalContact.name;
    newContact.displayName = originalContact.displayName;

    // Add all phones from original
    newContact.phones = List.from(originalContact.phones);

    // Add unique phones from duplicates
    for (var duplicate in duplicates) {
      for (var phone in duplicate.phones) {
        bool isDuplicate = originalContact.phones.any(
                (p) => _arePhonesSimilar(p.number, phone.number)
        );

        if (!isDuplicate) {
          print("Adding phone: ${phone.number}");
          newContact.phones.add(phone);
        }
      }
    }

    // Same for emails
    newContact.emails = List.from(originalContact.emails);
    for (var duplicate in duplicates) {
      for (var email in duplicate.emails) {
        bool isDuplicate = originalContact.emails.any(
                (e) => e.address.toLowerCase() == email.address.toLowerCase()
        );

        if (!isDuplicate) {
          newContact.emails.add(email);
        }
      }
    }

    // Same for addresses
    newContact.addresses = List.from(originalContact.addresses);
    for (var duplicate in duplicates) {
      for (var address in duplicate.addresses) {
        bool isDuplicate = originalContact.addresses.any(
                (a) => a.address == address.address
        );

        if (!isDuplicate) {
          newContact.addresses.add(address);
        }
      }
    }

    // Step 2: Insert the new merged contact
    print("Inserting new merged contact");
    final newId = await newContact.insert();
    print("New contact inserted with ID: $newId");

    // Step 3: Delete both original and duplicates
    print("Deleting original and duplicates");
    try {
      await originalContact.delete();
      print("Original deleted");
    } catch (e) {
      print("Error deleting original: $e");
    }

    for (var duplicate in duplicates) {
      try {
        await duplicate.delete();
        print("Duplicate deleted");
      } catch (e) {
        print("Error deleting duplicate: $e");
      }
    }

    return;
  }


  Future<void> backupContacts(BuildContext context) async {
    try {
      // Request contacts permission first
      if (!await FlutterContacts.requestPermission()) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Contact permission is required for backup'))
        );
        return;
      }

      // Show progress indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Creating Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Backing up contacts...'),
            ],
          ),
        ),
      );

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

      // Get path to Downloads folder
      final downloadsPath = await _getDownloadsPath();

      if (downloadsPath == null) {
        // Fallback to app's documents directory if Downloads is not accessible
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'contacts_backup_$timestamp.json';
        final backupFile = File('${directory.path}/$fileName');

        // Write contacts to file
        await backupFile.writeAsString(jsonEncode(contactsJson));

        // Close the progress dialog
        Navigator.of(context).pop();

        // Show dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup Created'),
            content: Text('${contacts.length} contacts backed up successfully.\n\nCould not access Downloads folder. Backup saved to app storage instead.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Share the file
                  await Share.shareFiles(
                    [backupFile.path],
                    text: 'Contact Backup (${contacts.length} contacts)',
                  );
                },
                child: const Text('Share Backup'),
              ),
            ],
          ),
        );
      } else {
        // Create backup in Downloads folder
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'contacts_backup_$timestamp.json';
        final backupFilePath = '$downloadsPath/$fileName';
        final backupFile = File(backupFilePath);

        // Write contacts to file
        await backupFile.writeAsString(jsonEncode(contactsJson));

        // Close the progress dialog
        Navigator.of(context).pop();

        // Show success dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup Created'),
            content: Text('${contacts.length} contacts backed up successfully.\n\nBackup saved to Downloads folder as:\n$fileName'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup completed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Close the progress dialog if it's open
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

// Helper method to get Downloads directory
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


  void _toggleAllSelection(bool? selected) {
    setState(() {
      for (var duplicate in _duplicateContacts) {
        duplicate.isSelected = selected ?? false;
      }
    });
  }

  Widget _buildMergeButton() {
    final selectedCount = _duplicateContacts.where((c) => c.isSelected).length;

    return FloatingActionButton.extended(
      onPressed: selectedCount > 0 ? _mergeSelectedContacts : null,
      backgroundColor: selectedCount > 0 ? Colors.blue : Colors.grey,
      label: Text('Merge $selectedCount'),
      icon: const Icon(Icons.merge_type),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _buildActionButtons(),
            _buildSelectionHeader(),
            Expanded(child: _buildContactsList()),
          ],
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: _buildMergeButton(),
        ),
      ],
    );
  }


  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
          builder: (context, constraints) {
            // Use constraints to make the layout responsive
            final buttonWidth = (constraints.maxWidth - 16) / 2; // Half width minus padding
            return Row(
              children: [
                Container(
                  width: buttonWidth,
                  child: _buildActionCard(
                    icon: Icons.backup_outlined,
                    label: 'Backup',  // Shorter label text
                    onTap: () => backupContactsAsVcf(context),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: buttonWidth,
                  child: _buildActionCard(
                    icon: Icons.restore_outlined,
                    label: 'Restore',  // Shorter label text
                    onTap: () => autoRestoreContacts(context),
                  ),
                ),
              ],
            );
          }
      ),
    );
  }

  Future<void> restoreContactsFromVcf(BuildContext context) async {
    try {
      // Step 1: Request contacts permission first
      if (!await FlutterContacts.requestPermission(readonly: false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contacts permission required for restore')),
        );
        return;
      }

      // Step 2: Open file picker to select VCF file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vcf'],
        dialogTitle: 'Select Contacts Backup (VCF) File',
      );

      // Check if user canceled selection
      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      // Step 3: Get selected file info
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      // Step 4: Show loading dialog
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
              Text('Reading VCF file...'),
            ],
          ),
        ),
      );

      // Step 5: Read and validate backup file
      final file = File(filePath);
      if (!await file.exists()) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: Backup file not found')),
        );
        return;
      }

      // Step 6: Read file content
      final String vcfContent;
      try {
        vcfContent = await file.readAsString();
        if (vcfContent.isEmpty) throw Exception('Backup file is empty');
      } catch (e) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading backup file: $e')),
        );
        return;
      }

      // Update loading message
      Navigator.of(context, rootNavigator: true).pop(); // Close first dialog
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
              Text('Restoring contacts from VCF file...'),
              SizedBox(height: 8),
              Text('This may take a moment', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );

      // Step 7: Process VCF content and restore contacts
      int restoredCount = 0;
      int skippedCount = 0;
      int errorCount = 0;

      // Split the VCF content into individual vCards
      // Each vCard starts with "BEGIN:VCARD" and ends with "END:VCARD"
      final RegExp vCardRegExp = RegExp(r'BEGIN:VCARD[\s\S]*?END:VCARD', multiLine: true);
      final matches = vCardRegExp.allMatches(vcfContent);

      // Get existing contacts to check for duplicates
      final existingContacts = await FlutterContacts.getContacts(
        withProperties: true,
      );

      // Process each vCard
      for (var match in matches) {
        try {
          final vCard = match.group(0)!;

          // Import the vCard to create a contact
          final contact = await Contact.fromVCard(vCard);

          // Check if this contact already exists
          bool isDuplicate = false;
          for (var existing in existingContacts) {
            // Compare names
            if (existing.displayName.toLowerCase() == contact.displayName.toLowerCase()) {
              // If both have phones, check if any phone numbers match
              if (existing.phones.isNotEmpty && contact.phones.isNotEmpty) {
                for (var phone in existing.phones) {
                  for (var newPhone in contact.phones) {
                    if (_arePhonesSimilar(phone.number, newPhone.number)) {
                      isDuplicate = true;
                      break;
                    }
                  }
                  if (isDuplicate) break;
                }
              }
            }
            if (isDuplicate) break;
          }

          if (!isDuplicate) {
            // Insert the contact
            await contact.insert();
            restoredCount++;
          } else {
            skippedCount++;
          }
        } catch (e) {
          print('Error restoring contact: $e');
          errorCount++;
        }
      }

      // Step 8: Show results dialog
      Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Restore Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Results:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Text('$restoredCount contacts restored'),
                ],
              ),
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Text('$skippedCount duplicates skipped'),
                ],
              ),
              if (errorCount > 0) ...[
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text('$errorCount errors'),
                  ],
                ),
              ],
              SizedBox(height: 16),
              Text('From backup file:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(fileName, style: TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Done'),
            ),
          ],
        ),
      );

      // Success notification
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore completed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Close any open dialogs
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Also make sure you have this helper function somewhere in your class
  bool _arePhonesSimilar(String phone1, String phone2) {
    // Normalize phone numbers (remove non-digits)
    final normalized1 = phone1.replaceAll(RegExp(r'[^\d]'), '');
    final normalized2 = phone2.replaceAll(RegExp(r'[^\d]'), '');

    // Compare the last 9 digits (to handle different country codes)
    if (normalized1.length >= 9 && normalized2.length >= 9) {
      final end1 = normalized1.substring(normalized1.length - 9);
      final end2 = normalized2.substring(normalized2.length - 9);
      return end1 == end2;
    }

    // If numbers are shorter, compare them directly
    return normalized1 == normalized2;
  }



  Future<void> autoRestoreContacts(BuildContext context) async {
    try {
      // Step 1: Request contacts permission first
      if (!await FlutterContacts.requestPermission(readonly: false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contacts permission required for restore')),
        );
        return;
      }

      // Step 2: Show initial loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Finding Backup Files'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Searching for contact backups...'),
            ],
          ),
        ),
      );

      // Step 3: Find the most recent backup file
      File? mostRecentBackup = await _findMostRecentBackup();

      // Close the initial loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      if (mostRecentBackup == null) {
        // No backup file found - ask user to select one manually
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No backup files found. Please select a backup file manually.'),
            duration: Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Select File',
              onPressed: () {
                // Fall back to manual selection
                restoreContactsFromVcf(context);
              },
            ),
          ),
        );
        return;
      }

      // Step 4: Show confirmation dialog with backup file info
      final fileName = mostRecentBackup.path.split('/').last;
      final fileStats = await mostRecentBackup.stat();
      final fileDate = DateTime.fromMillisecondsSinceEpoch(
          fileStats.modified.millisecondsSinceEpoch);

      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Restore Contacts'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Found a contacts backup:'),
              SizedBox(height: 12),
              Text(fileName, style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                'Created on: ${_formatDate(fileDate)}',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              SizedBox(height: 16),
              Text('Do you want to restore contacts from this backup?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);

                // Offer manual selection as an alternative
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Restore canceled. Select a different backup file?'),
                    action: SnackBarAction(
                      label: 'Select File',
                      onPressed: () {
                        // Fall back to manual selection
                        restoreContactsFromVcf(context);
                      },
                    ),
                  ),
                );
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Restore'),
            ),
          ],
        ),
      ) ?? false;

      if (!shouldRestore) {
        return; // User canceled
      }

      // Step 5: Show loading dialog for restoration
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
              Text('Reading backup file...'),
            ],
          ),
        ),
      );

      // Step 6: Read file content
      final String vcfContent;
      try {
        vcfContent = await mostRecentBackup.readAsString();
        if (vcfContent.isEmpty) throw Exception('Backup file is empty');
      } catch (e) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading backup file: $e')),
        );
        return;
      }

      // Update loading message
      Navigator.of(context, rootNavigator: true).pop(); // Close first dialog
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
              Text('Restoring contacts from backup...'),
              SizedBox(height: 8),
              Text('This may take a moment', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );

      // Step 7: Process VCF content and restore contacts
      int restoredCount = 0;
      int skippedCount = 0;
      int errorCount = 0;

      // Split the VCF content into individual vCards
      // Each vCard starts with "BEGIN:VCARD" and ends with "END:VCARD"
      final RegExp vCardRegExp = RegExp(r'BEGIN:VCARD[\s\S]*?END:VCARD', multiLine: true);
      final matches = vCardRegExp.allMatches(vcfContent);

      // Get existing contacts to check for duplicates
      final existingContacts = await FlutterContacts.getContacts(
        withProperties: true,
      );

      // Process each vCard
      for (var match in matches) {
        try {
          final vCard = match.group(0)!;

          // Import the vCard to create a contact
          final contact = await Contact.fromVCard(vCard);

          // Check if this contact already exists
          bool isDuplicate = false;
          for (var existing in existingContacts) {
            // Compare names
            if (existing.displayName.toLowerCase() == contact.displayName.toLowerCase()) {
              // If both have phones, check if any phone numbers match
              if (existing.phones.isNotEmpty && contact.phones.isNotEmpty) {
                for (var phone in existing.phones) {
                  for (var newPhone in contact.phones) {
                    if (_arePhonesSimilar(phone.number, newPhone.number)) {
                      isDuplicate = true;
                      break;
                    }
                  }
                  if (isDuplicate) break;
                }
              }
            }
            if (isDuplicate) break;
          }

          if (!isDuplicate) {
            // Insert the contact
            await contact.insert();
            restoredCount++;
          } else {
            skippedCount++;
          }
        } catch (e) {
          print('Error restoring contact: $e');
          errorCount++;
        }
      }

      // Step 8: Close the loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      // Instead of showing a results dialog, just show a concise snackbar
      String message = 'Restored $restoredCount contacts';
      if (skippedCount > 0) {
        message += ', skipped $skippedCount duplicates';
      }
      if (errorCount > 0) {
        message += ', encountered $errorCount errors';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contacts restored successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      // Close any open dialogs
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }




  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Colors.blue),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
      ),
    );
  }




  Widget _buildSelectionHeader() {
    final selectedCount = _duplicateContacts.where((c) => c.isSelected).length;
    final totalCount = _duplicateContacts.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
          builder: (context, constraints) {
            // Check if we need a more compact layout for smaller screens
            final isCompact = constraints.maxWidth < 360;

            if (isCompact) {
              // Vertical layout for very small screens
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$selectedCount/$totalCount selected',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _toggleAllSelection(true),
                        child: const Text(
                          'Select All',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: Size.zero, // Set minimum size to zero
                        ),
                      ),
                      TextButton(
                        onPressed: () => _toggleAllSelection(false),
                        child: const Text(
                          'Deselect All',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: Size.zero, // Set minimum size to zero
                        ),
                      ),
                    ],
                  ),
                ],
              );
            } else {
              // Normal layout for standard screens
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Use Flexible to allow text to shrink if needed
                  Flexible(
                    child: Text(
                      '$selectedCount/$totalCount selected',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min, // Don't expand unnecessarily
                    children: [
                      TextButton(
                        onPressed: () => _toggleAllSelection(true),
                        child: const Text(
                          'Select All',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: Size.zero, // Reduce minimum size
                        ),
                      ),
                      TextButton(
                        onPressed: () => _toggleAllSelection(false),
                        child: const Text(
                          'Deselect All',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: Size.zero, // Reduce minimum size
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }
          }
      ),
    );
  }

  Widget _buildContactsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_duplicateContacts.isEmpty) {
      return Center(
        child: Text(
          'No duplicate contacts found',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _duplicateContacts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildContactItem(_duplicateContacts[index]),
    );
  }



  Widget _buildContactItem(DuplicateContact contact) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          child: Text(
            contact.originalContact.displayName.isNotEmpty
                ? contact.originalContact.displayName[0].toUpperCase()
                : '?',
            style: const TextStyle(color: Colors.blue),
          ),
        ),
        title: Text(
          contact.originalContact.displayName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          // Allow text to wrap or truncate if too long
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                // Set explicit width constraint to prevent overflow
                width: constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Display all phone numbers for original contact (limited to 2)
                    ...contact.originalContact.phones.take(2).map((phone) => Text(
                      phone.number,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )).toList(),
                    // Only show "and more..." if there are additional phones
                    if (contact.originalContact.phones.length > 2 ||
                        contact.duplicates.any((d) => d.phones.isNotEmpty))
                      Text(
                        "...",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              );
            }
        ),
        trailing: SizedBox(
          // Fixed size for trailing widget to prevent overflow
          width: 24,
          height: 24,
          child: Checkbox(
            value: contact.isSelected,
            onChanged: (value) {
              setState(() {
                contact.isSelected = value ?? false;
              });
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            activeColor: Colors.blue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // Make target smaller
          ),
        ),
      ),
    );
  }

  Future<File?> _findMostRecentBackup() async {
    List<File> backupFiles = [];

    // Look in app's documents directory first
    try {
      final directory = await getApplicationDocumentsDirectory();
      final dir = Directory(directory.path);
      final entities = await dir.list().toList();

      for (var entity in entities) {
        if (entity is File &&
            (entity.path.endsWith('.vcf') || entity.path.endsWith('.json')) &&
            entity.path.contains('contacts_backup')) {
          backupFiles.add(entity);
        }
      }
    } catch (e) {
      print('Error checking app directory: $e');
    }

    // Look in downloads folder
    try {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final entities = await downloadsDir.list().toList();

        for (var entity in entities) {
          if (entity is File &&
              (entity.path.endsWith('.vcf') || entity.path.endsWith('.json')) &&
              entity.path.contains('contacts_backup')) {
            backupFiles.add(entity);
          }
        }
      }
    } catch (e) {
      print('Error checking downloads directory: $e');
    }

    // If we found backup files, sort them by modification time (newest first)
    if (backupFiles.isNotEmpty) {
      backupFiles.sort((a, b) {
        final statA = a.statSync();
        final statB = b.statSync();
        return statB.modified.compareTo(statA.modified);
      });

      // Return the most recent file
      return backupFiles.first;
    }

    return null; // No backup files found
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today, ${_formatTime(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday, ${_formatTime(date)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago, ${_formatTime(date)}';
    } else {
      return '${date.day}/${date.month}/${date.year}, ${_formatTime(date)}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }


  Future<void> backupContactsAsVcf(BuildContext context) async {
    try {
      // Request contacts permission first
      if (!await FlutterContacts.requestPermission()) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Contact permission is required for backup'))
        );
        return;
      }

      // Show progress indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Creating Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Backing up contacts...'),
            ],
          ),
        ),
      );

      // Get all contacts with properties and photos
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
        withGroups: true,
        withAccounts: true,
      );

      // Create VCF content
      final StringBuffer vcfContent = StringBuffer();

      for (var contact in contacts) {
        // Export each contact to vCard format
        final String vCard = await contact.toVCard();
        vcfContent.write(vCard);

        // Add a blank line between contacts if not already included
        if (!vCard.endsWith('\n\n')) {
          vcfContent.write('\n');
        }
      }

      // Create backup file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'contacts_backup_$timestamp.vcf';
      final backupFile = File('${directory.path}/$fileName');

      // Write VCF content to file
      await backupFile.writeAsString(vcfContent.toString());

      // Try to also save to Downloads directory for easier access
      try {
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (await downloadsDir.exists()) {
          final downloadFilePath = '${downloadsDir.path}/$fileName';
          final downloadFile = File(downloadFilePath);
          await downloadFile.writeAsString(vcfContent.toString());
        }
      } catch (e) {
        print('Could not save to Downloads directory: $e');
        // This is not critical, so we continue execution
      }

      // Close the progress dialog
      Navigator.of(context).pop();

      // Show simple success notification with file location information
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${contacts.length} contacts backed up successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      // Close the progress dialog if it's open
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}




class DuplicateContact {
  final Contact originalContact;
  final List<Contact> duplicates;
  bool isSelected;

  DuplicateContact({
    required this.originalContact,
    required this.duplicates,
    this.isSelected = true,
  });
}