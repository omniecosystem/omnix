import 'package:test/test.dart';
import 'package:omnix_example/features/nexus/data/public_fixture.dart';

void main() {
  const fixture =
      '[{"title":"Private note","content":"secret","access":"private"},{"title":"Router","content":"Hold reset","access":"public"}]';
  test('only public matching fixtures can be disclosed', () {
    expect(answerPublicFixture(fixture, 'private note'), isEmpty);
    expect(
      answerPublicFixture(fixture, 'router'),
      'Hold reset\nSource: Router',
    );
    expect(answerPublicFixture(fixture, 'unrelated'), isEmpty);
    expect(answerPublicFixture(fixture, ''), isEmpty);
  });
  test('rejects malformed input', () {
    expect(() => answerPublicFixture('{}', 'router'), throwsFormatException);
  });
}
