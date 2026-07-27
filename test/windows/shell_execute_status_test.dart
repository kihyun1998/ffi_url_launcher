@TestOn('vm')
library;

import 'package:ffi_url_launcher/src/backends/windows/shell_execute.dart';
import 'package:test/test.dart';

// Every value asserted here was read out of the Windows SDK headers on a real
// machine, not recited:
//   shellapi.h:366-380  SE_ERR_FNF 2, PNF 3, ACCESSDENIED 5, OOM 8,
//                       SHARE 26, ASSOCINCOMPLETE 27, DDETIMEOUT 28,
//                       DDEFAIL 29, DDEBUSY 30, NOASSOC 31, DLLNOTFOUND 32
//   shellapi.h:103      `_Success_(return > 32)`
void main() {
  group('interpretShellExecuteStatus', () {
    test('treats anything greater than 32 as launched', () {
      expect(interpretShellExecuteStatus(33), ShellExecuteOutcome.launched);
      expect(interpretShellExecuteStatus(42), ShellExecuteOutcome.launched);
    });

    test('treats 32 itself as a failure, not a success', () {
      // SE_ERR_DLLNOTFOUND is exactly 32, and the header's success predicate is
      // `> 32`. An off-by-one here turns a failure into a silent success.
      expect(interpretShellExecuteStatus(32), ShellExecuteOutcome.failed);
    });

    test('treats SE_ERR_NOASSOC as "no handler", not as a failure', () {
      // 31 means nothing is registered to open this. That is an ordinary
      // answer, not a fault, so it must not become an exception.
      expect(interpretShellExecuteStatus(31), ShellExecuteOutcome.noHandler);
    });

    test('treats every other documented error code as a failure', () {
      for (final status in [0, 2, 3, 5, 8, 26, 27, 28, 29, 30]) {
        expect(
          interpretShellExecuteStatus(status),
          ShellExecuteOutcome.failed,
          reason: 'status $status should be a failure',
        );
      }
    });
  });

  group('describeShellExecuteStatus', () {
    test('names the codes a caller is most likely to hit', () {
      expect(describeShellExecuteStatus(2), contains('not found'));
      expect(describeShellExecuteStatus(5), contains('denied'));
    });

    test('falls back to the raw code rather than hiding it', () {
      // 7 is not one of the documented SE_ERR_* values, so it has no name to
      // print. Swallowing it into a vague sentence is what leaves a caller with
      // nothing to search for.
      expect(describeShellExecuteStatus(7), contains('7'));
    });

    test('names every documented code instead of falling back', () {
      // The fallback exists for the undocumented tail, not as a way to avoid
      // writing the messages. If one of these starts printing its number, a
      // case was dropped from the switch.
      for (final status in [2, 3, 5, 8, 26, 27, 28, 29, 30, 31, 32]) {
        expect(
          describeShellExecuteStatus(status),
          isNot(contains('$status')),
          reason: 'status $status should have a named message',
        );
      }
    });

    test('never describes SE_ERR_NOASSOC as an error', () {
      // 31 never reaches this function — it is answered as `false` upstream.
      // If it ever does, the message must not tell the user something broke.
      expect(describeShellExecuteStatus(31), isNot(contains('error')));
    });
  });
}
