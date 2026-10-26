import 'package:flutter_test/flutter_test.dart';
import 'package:photolib_api/photolib_api.dart';

import '../support/console.dart';
import '../support/fake_server.dart';

/// The onboarding half of the admin-succession kit (design 15 §6): the console
/// asks for a second active administrator.
void main() {
  User admin(String handle, UserStatus status) => User(
    userId: handle,
    handle: handle,
    displayName: handle,
    role: UserRole.USER_ROLE_ADMIN,
    status: status,
  );
  for (final (name, bob, asks) in [
    ('one administrator is asked for a second', null, true),
    (
      'a disabled second administrator does not count',
      admin('bob', UserStatus.USER_STATUS_DISABLED),
      true,
    ),
    (
      'two administrators are not asked for another',
      admin('bob', UserStatus.USER_STATUS_ACTIVE),
      false,
    ),
  ]) {
    testWidgets(name, (tester) async {
      await openConsole(
        tester,
        FakeServer({
          'UserService/ListUsers': (_) => ListUsersResponse(
            users: [admin('ann', UserStatus.USER_STATUS_ACTIVE), ?bob],
          ),
        }),
      );
      await section(tester, 'Accounts');
      expect(
        find.text(
          'Make a second person an administrator, so that someone else can '
          'run and restore the server if you cannot.',
        ),
        asks ? findsOneWidget : findsNothing,
      );
    });
  }
}
