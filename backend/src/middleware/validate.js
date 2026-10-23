const { badRequest } = require('../lib/errors');

/**
 * validate({ body, query, params }) — each a zod schema. Parsed values replace
 * the originals (req.query is read-only in Express 5, so parsed query goes to req.q).
 */
function validate(schemas) {
  return (req, _res, next) => {
    for (const source of ['params', 'query', 'body']) {
      const schema = schemas[source];
      if (!schema) continue;
      const result = schema.safeParse(req[source] ?? {});
      if (!result.success) {
        const details = result.error.issues.map((i) => ({ field: i.path.join('.'), message: i.message }));
        return next(badRequest(details[0] ? `${details[0].field || source}: ${details[0].message}` : 'Invalid input', details));
      }
      if (source === 'query') req.q = result.data;
      else req[source] = result.data;
    }
    return next();
  };
}

module.exports = { validate };
