// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test_runner.runner;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:coverage/src/devtools.dart';
import 'package:coverage/src/util.dart';
import 'package:unittest/unittest.dart';
import 'dart_binaries.dart';
import 'test_configuration.dart';
import 'dart_project.dart';

part "runners/vm_test_runner.dart";
part "runners/browser_test_runner.dart";
part "runners/browser_templates/browser_test_dart_template.dart";
part "runners/browser_templates/browser_test_html_template.dart";
part "runners/vm_templates/vm_test_dart_template.dart";

/// Implementations runs dart tests in a particular environment.
abstract class TestRunner {

  /// Runs the [test] and returns the [TestExecutionResult].
  Future<TestExecutionResult> runTest(TestConfiguration test);
}

/// Describes the result of executing a Dart test.
class TestExecutionResult {

  /// Constructor.
  TestExecutionResult(this.test, {this.success: true, this.testOutput: "",
      this.testErrorOutput: ""});

  /// Construct a new [TestExecutionResult] from JSON.
  TestExecutionResult.fromJson(var json, this.test) {
    success = json["success"];
    testOutput = json["testOutput"];
    testErrorOutput = json["testErrorOutput"];
    if (success == null || testOutput == null || testErrorOutput == null) {
      throw new ArgumentError("TestExecutionResult JSON is missing values.");
    }
  }

  /// [true] if the test file succeeded.
  bool success;

  /// What was printed on the standard output by the [UnitTest] library.
  String testOutput;

  /// What was printed on the error output by the [UnitTest] library.
  String testErrorOutput;

  /// Pointer to the test.
  TestConfiguration test;
}

/// Properly dispatch running tests to the correct [TestRunner].
class TestRunnerDispatcher {

  /// Number of seconds to wait until the test times out.
  static const int TESTS_TIMEOUT_SEC = 240;

  /// Pointers to all Dart SDK binaries.
  DartBinaries dartBinaries;

  /// The Dart project containing the tests.
  DartProject dartProject;

  /// Constructor.
  TestRunnerDispatcher(this.dartBinaries, this.dartProject);

  /// Runs all the given [tests].
  ///
  /// TODO: Implement @NotParallelizable
  /// TODO: Implement a pool of X (5?) number of tests ran at a time.
  Stream<TestExecutionResult> runTests(List<TestConfiguration> tests) {

    // We create a Stream so that we can display in real time results of tests
    // that completed.
    StreamController<TestExecutionResult> controller =
        new StreamController<TestExecutionResult>.broadcast();

    // We list the futures so that we can wait for all of them to complete in
    // order to close the Stream.
    List<Future<TestExecutionResult>> testRunnerResultFutures =
        new List<Future<TestExecutionResult>>();

    // For each Test we find the correct TestRunner and run the test with it.
    for (TestConfiguration test in tests) {
      TestRunner testRunner;
      if (test.testType is VmTest) {
        testRunner = new VmTestRunner(dartBinaries, dartProject);
      } else if (test.testType is BrowserTest) {
        testRunner = new BrowserTestRunner(dartBinaries, dartProject);
      }

      // Execute test and send result to the stream.
      Future<TestExecutionResult> stuff = testRunner
          .runTest(test)
          // Kill the test after a set amount of time. Timeout.
          .timeout(new Duration(seconds: TESTS_TIMEOUT_SEC), onTimeout: () {
            TestExecutionResult result = new TestExecutionResult(test);
            result.success = false;
            result.testOutput = "The test did not complete in less than "
                                "$TESTS_TIMEOUT_SEC seconds. It was aborted.";
            return result;
          })..then((TestExecutionResult result) {
            controller.add(result);
          });

      // Adding the test Future to the list of tests to watch.
      testRunnerResultFutures.add(stuff);
    }

    // When all tests are completed we close the stream.
    Future.wait(testRunnerResultFutures).then((_) => controller.close());

    return controller.stream;
  }
}

/// Provides base class for Code Generators so that they can easily access the
/// Generated test files directory.
abstract class TestRunnerCodeGenerator {

  /// Name of the directory that will contain the test files generated by the
  /// test runner.
  static const String GENERATED_TEST_FILES_DIR_NAME = "__test_runner";

  /// Directory where all the generated test runner files are created.
  Directory generatedTestFilesDirectory;

  /// Pointers to the Dart Project containing the tests.
  final DartProject dartProject;

  /// Constructor.
  TestRunnerCodeGenerator(this.dartProject) {
    generatedTestFilesDirectory = _createGeneratedTestFilesDirectory();
  }

  /// Returns the directory named [GENERATED_TEST_FILES_DIR_NAME] in the
  /// [dartProject]'s test directory and creates it if it doesn't exists.
  ///
  /// Throws a [FileExistsException] if there is already a [FileSystemEntity]
  /// with the same name that's not a [Directory].
  Directory _createGeneratedTestFilesDirectory() {
    String generatedTestFilesDirectoryPath =
        dartProject.testDirectory.resolveSymbolicLinksSync() + "/"
            + GENERATED_TEST_FILES_DIR_NAME;

    Directory newGeneratedSourceDir =
        new Directory(generatedTestFilesDirectoryPath);
    FileSystemEntityType dirType =
        FileSystemEntity.typeSync(generatedTestFilesDirectoryPath);
    if (dirType == FileSystemEntityType.NOT_FOUND) {
      newGeneratedSourceDir.createSync();
    } else if (dirType != FileSystemEntityType.DIRECTORY) {
      throw new FileExistsException("$generatedTestFilesDirectoryPath already "
          "exists and is not a Directory.");
    }
    return newGeneratedSourceDir;
  }

  /// Deletes the Generated test files directory of a given [dartProject].
  ///
  /// Returns [True] if a directory existed and was deleted and [False] if there
  /// was no directory.
  static bool deleteGeneratedTestFilesDirectory(DartProject dartProject) {
    String generatedTestFilesDirectoryPath =
        dartProject.testDirectory.resolveSymbolicLinksSync() + "/"
            + GENERATED_TEST_FILES_DIR_NAME;

    Directory newGeneratedSourceDir =
        new Directory(generatedTestFilesDirectoryPath);

    if (newGeneratedSourceDir.existsSync()) {
      newGeneratedSourceDir.deleteSync(recursive: true);
      return true;
    }
    return false;
  }
}

/// Exception used if a file exists that was not supposed to.
class FileExistsException extends Exception {
  factory FileExistsException([var message]) => new Exception(message);
}
