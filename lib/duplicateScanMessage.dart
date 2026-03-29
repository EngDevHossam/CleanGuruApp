

import 'dart:isolate';

class DuplicateScanMessage {
  final List<String> directories;
  final SendPort responsePort;

  DuplicateScanMessage(this.directories, this.responsePort);

}
