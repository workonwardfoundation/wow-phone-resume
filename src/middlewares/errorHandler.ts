// src/middlewares/errorHandler.js

import { FastifyError, FastifyReply, FastifyRequest } from 'fastify';

/**
 * Centralized error handling middleware.
 * @param {Error} error - The error thrown.
 * @param {object} request - The Fastify request.
 * @param {object} reply - The Fastify reply.
 */
export function errorHandler(
  error: FastifyError,
  request: FastifyRequest,
  reply: FastifyReply
) {
  request.log.error(error);
  reply.status(error.statusCode || 500).send({
    error: error.message || 'Internal Server Error',
  });
}
