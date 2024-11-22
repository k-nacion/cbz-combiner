import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:console_bars/console_bars.dart';

void main() {
  final view = FileProcessorView();
  final model = FileProcessorModel();
  final viewModel = FileProcessorViewModel(view, model);

  viewModel.run();
}

// --- View ---
class FileProcessorView {
  String? prompt(String message) {
    print(message);
    return stdin.readLineSync();
  }

  void displayMessage(String message) {
    print(message);
  }

  void displayError(String errorMessage) {
    print('Error: $errorMessage');
  }

  void displayProgress(FillingBar fillingBar, increment) {}
}

// --- Model ---
class FileProcessorModel {
  Future<Archive> processFile(File file, Logger logger, int totalSteps, int step) async {
    final archive = Archive();

    try {
      final inputStream = InputFileStream(file.path);
      final fileArchive = ZipDecoder().decodeBuffer(inputStream);

      for (final archiveFile in fileArchive.files) {
        if (archiveFile.isFile) {
          final content = archiveFile.content as List<int>;
          final archiveFileName = '${file.uri.pathSegments.last} - ${archiveFile.name}';
          archive.addFile(ArchiveFile(archiveFileName, content.length, content));
        }
      }

      logger.progress('${(step / totalSteps * 100).toStringAsFixed(1)}% completed...');
    } catch (e) {
      print('Error processing file ${file.path}: $e');
    }

    return archive;
  }

  Future<void> saveSplitArchives(Archive archive, Directory outputDir, double maxSizeBytes, String baseName) async {
    final zipEncoder = ZipEncoder();
    int fileIndex = 1;
    int currentSize = 0;
    Archive currentArchive = Archive();

    for (var file in archive.files) {
      if (currentSize + file.size <= maxSizeBytes) {
        currentArchive.addFile(file);
        currentSize += file.size;
      } else {
        await _saveArchiveToFile(zipEncoder, currentArchive, outputDir, baseName, fileIndex);
        fileIndex++;
        currentArchive = Archive();
        currentArchive.addFile(file);
        currentSize = file.size;
      }
    }

    if (currentArchive.isNotEmpty) {
      await _saveArchiveToFile(zipEncoder, currentArchive, outputDir, baseName, fileIndex);
    }
  }

  Future<void> _saveArchiveToFile(
      ZipEncoder encoder, Archive archive, Directory outputDir, String baseName, int fileIndex) async {
    final encodedArchive = encoder.encode(archive);
    if (encodedArchive != null) {
      final outputPath = '${outputDir.path}${Platform.pathSeparator}${baseName}_$fileIndex.cbz';
      await File(outputPath).writeAsBytes(encodedArchive);
      print('Saved archive: $outputPath');
    }
  }
}

// --- ViewModel ---
class FileProcessorViewModel {
  final FileProcessorView _view;
  final FileProcessorModel _model;

  FileProcessorViewModel(this._view, this._model);

  Future<void> run() async {
    final inputDirPath = _view.prompt('Enter the directory path to look from:');
    final inputSizeLimit = _view.prompt('Enter the maximum size for output files (in MB):');

    if (inputDirPath == null ||
        inputDirPath.isEmpty ||
        inputSizeLimit == null ||
        double.tryParse(inputSizeLimit) == null) {
      _view.displayError('Invalid input.');
      return;
    }

    final maxSizeBytes = double.parse(inputSizeLimit) * 1024 * 1024;
    final inputDir = Directory(inputDirPath);

    if (!await inputDir.exists()) {
      _view.displayError('Directory does not exist!');
      return;
    }

    final baseName = inputDir.uri.pathSegments.isNotEmpty
        ? inputDir.uri.pathSegments[inputDir.uri.pathSegments.length - 2]
        : 'output';

    final outputDir = Directory('output');
    await outputDir.create();

    final resultArchive = Archive();

    final logger = Logger.standard();

    try {
      final files = await inputDir.list().toList();

      for (var i = 0; i < files.length; i++) {
        if (files[i] is File) {
          final file = files[i] as File;
          final archive = await _model.processFile(file, logger, files.length, i + 1);
          for (var archiveFile in archive.files) {
            resultArchive.addFile(archiveFile);
          }
        }
      }

      await _model.saveSplitArchives(resultArchive, outputDir, maxSizeBytes, baseName);
      _view.displayMessage('Process completed successfully!');
    } catch (e) {
      _view.displayError('An error occurred: $e');
    }
  }
}
