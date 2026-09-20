import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixToolInputValidator', () {
    test('accepts arguments matching nested schemas', () {
      final result = OmnixToolInputValidator.validate(_schema, const {
        'query': 'local news',
        'limit': 3,
        'filters': ['recent', 'english'],
      });

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('reports missing, mistyped, nested, and additional arguments', () {
      final result = OmnixToolInputValidator.validate(_schema, const {
        'limit': 'three',
        'filters': ['recent', 7],
        'unknown': true,
      });

      expect(result.isValid, isFalse);
      expect(
        result.issues.map((issue) => issue.path),
        containsAll([r'$.query', r'$.limit', r'$.filters[1]', r'$.unknown']),
      );
    });

    test('validates enum values', () {
      final result = OmnixToolInputValidator.validate(
        const {
          'type': 'object',
          'properties': {
            'format': {
              'type': 'string',
              'enum': ['short', 'long'],
            },
          },
        },
        const {'format': 'medium'},
      );

      expect(result.issues.single.path, r'$.format');
      expect(result.issues.single.message, contains('enum'));
    });
  });
}

const _schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'query': {'type': 'string'},
    'limit': {'type': 'integer'},
    'filters': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'required': ['query'],
  'additionalProperties': false,
};
