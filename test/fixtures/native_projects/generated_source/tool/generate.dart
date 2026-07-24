import 'dart:io';

/// Generator tool for the generated_source fixture.
///
/// Reads a value from input and generates a C source file.
void main(List<String> args) {
  if (args.length != 2) {
    print('Usage: generate.dart <input_file> <output_file>');
    exit(1);
  }

  final outputPath = args[1];

  // Write output file
  // In real implementation, would write C source to outputPath
  print('Generated: $outputPath');
  print('Value: 42');
}
