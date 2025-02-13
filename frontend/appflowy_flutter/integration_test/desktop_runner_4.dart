import 'package:integration_test/integration_test.dart';

import 'desktop/document/document_test_runner_2.dart' as document_test_runner_2;
import 'desktop/grid/grid_calculations_test.dart' as grid_calculations_test;
import 'desktop/first_test/first_test.dart' as first_test;

Future<void> main() async {
  await runIntegration4OnDesktop();
}

Future<void> runIntegration4OnDesktop() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  first_test.main();

  document_test_runner_2.main();
  grid_calculations_test.main();
  // DON'T add more tests here.
}
