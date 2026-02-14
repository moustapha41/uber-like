/**
 * Standardized API response helpers
 * Signature: successResponse(res, data, message, statusCode)
 * Tolérant: si le 3e argument est un nombre et le 4e une string, on les intervertit.
 */
const successResponse = (res, data, message = 'Success', statusCode = 200) => {
  if (typeof message === 'number' && typeof statusCode === 'string') {
    [message, statusCode] = [statusCode, message];
  }
  const code = typeof statusCode === 'number' ? statusCode : 200;
  return res.status(code).json({
    success: true,
    message: typeof message === 'string' ? message : 'Success',
    data
  });
};

const errorResponse = (res, message = 'Error', statusCode = 400) => {
  return res.status(statusCode).json({
    success: false,
    message
  });
};

module.exports = {
  successResponse,
  errorResponse
};

