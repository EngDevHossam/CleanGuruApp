import 'dart:io' as io;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

import 'dart:io' as io;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;


class GoogleDriveBackup {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '37238765627-t9rslbnq7jr7ede1kl84g5n0pi05hi23.apps.googleusercontent.com', // Added client ID

    scopes: [
      drive.DriveApi.driveFileScope,
      'email',
      'profile'
    ],

  );


  Future<void> backupContacts(io.File contactsFile) async {
    try {
      print("Starting Google Sign-In process");

      // Check if file exists and is readable
      if (!await contactsFile.exists()) {
        throw Exception('Backup file does not exist');
      }

      final fileSize = await contactsFile.length();
      print("File exists, size: $fileSize bytes");

      if (fileSize <= 0) {
        throw Exception('Backup file is empty');
      }

      // Authenticate
      print("Requesting Google Sign-In");
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

    if (account == null) {
    print("Sign-in canceled or failed");
    throw Exception('Sign-in canceled or failed');
    }

    print("Signed in as: ${account.email}");
    print("Requesting authentication tokens");

    final GoogleSignInAuthentication? authentication = await account.authentication;

    if (authentication == null || authentication.accessToken == null) {
    print("Authentication failed, tokens not received");
    throw Exception('Authentication failed');
    }

    print("Authentication successful, received access token");

    // Create authorized client using access token
    final authClient = auth.authenticatedClient(
    http.Client(),
    auth.AccessCredentials(
    auth.AccessToken(
    'Bearer',
    authentication.accessToken!,
    DateTime.now().add(const Duration(hours: 1)),
    ),
    null, // No refresh token
    [],
    ),
    );

    print("Created authorized HTTP client");

    // Create Drive API instance
    final driveApi = drive.DriveApi(authClient);
    print("Initialized Drive API");

    // Prepare file metadata
    final fileName = 'contacts_backup_${DateTime.now().millisecondsSinceEpoch}.vcf';
    final driveFile = drive.File()
    ..name = fileName
    ..mimeType = 'text/vcard';

    print("Prepared file metadata for upload: $fileName");

    // Upload file
    print("Starting file upload to Google Drive");
    final result = await driveApi.files.create(
    driveFile,
    uploadMedia: drive.Media(contactsFile.openRead(), contactsFile.lengthSync()),
    );

    print("Upload complete. File ID: ${result.id}");

    } catch (e, stack) {
    print('Google Drive backup error: $e');
    print('Stack trace: $stack');
    rethrow;
    }
  }

  // Method to check if user is already signed in
  Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      print('Error checking sign-in status: $e');
      return false;
    }
  }

  // Method to sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      print('Successfully signed out');
    } catch (e) {
      print('Error signing out: $e');
      rethrow;
    }
  }
}

