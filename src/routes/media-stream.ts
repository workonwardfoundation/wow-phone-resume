// src/routes/mediaStreamRoutes.js
import { FastifyInstance } from 'fastify';
import { handleMediaStream } from '../controllers/mediaStream';

export const autoPrefix = '/media-stream';

export default function mediaStreamRoutes(fastify: FastifyInstance) {
  fastify.get('/', { websocket: true }, (connection, req) => {
    handleMediaStream(connection, req);
  });
}
