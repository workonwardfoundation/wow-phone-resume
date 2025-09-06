import { FastifyPluginAsync } from 'fastify';
import autoload from '@fastify/autoload';
import { errorHandler } from '@/middlewares/errorHandler';
import fastifyFormBody from '@fastify/formbody';
import fastifyWs from '@fastify/websocket';
import mongoose from 'mongoose';
import path from 'path';

const MONGODB_URL = `${process.env.DB_URL}/wow-agent`;

const app: FastifyPluginAsync = async (fastify): Promise<void> => {
  // Register plugins first
  fastify.register(fastifyFormBody);
  fastify.register(fastifyWs);
  
  // MongoDB connection with better error handling
  fastify.register((fastifyInstance, _, done) => {
    if (!process.env.DB_URL) {
      fastify.log.warn('DB_URL environment variable not set. MongoDB features will be disabled.');
      done();
      return;
    }

    fastify.log.info(`⚛️ connecting mongodb....\n${MONGODB_URL}`);
    mongoose
      .connect(MONGODB_URL)
      .then(() => {
        fastify.log.info(`⚛️  db successfully connected`);
      })
      .catch((e) => {
        fastify.log.error(`⚛️  db connection failure - ${e}`);
        // Don't close the app, just log the error
        fastify.log.warn('Continuing without database connection');
      })
      .finally(() => done());
  });

  fastify.register(autoload, {
    dir: path.join(__dirname, 'routes'),
    options: { prefix: '/api/v1' },
  });
  
  //  Centralized error handling
  fastify.setErrorHandler(errorHandler);
};

export default app;
