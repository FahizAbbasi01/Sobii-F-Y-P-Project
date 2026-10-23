class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

const badRequest = (message, details) => new ApiError(400, 'bad_request', message, details);
const unauthorized = (message = 'Authentication required') => new ApiError(401, 'unauthorized', message);
const forbidden = (message = 'You are not allowed to do this') => new ApiError(403, 'forbidden', message);
const notFound = (message = 'Not found') => new ApiError(404, 'not_found', message);
const conflict = (message, code = 'conflict') => new ApiError(409, code, message);

module.exports = { ApiError, badRequest, unauthorized, forbidden, notFound, conflict };
