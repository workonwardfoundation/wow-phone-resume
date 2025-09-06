import './set-env';

import Fastify from 'fastify';
import app from '@/app';
import closeWithGrace from 'close-with-grace';
import { initSwagger } from '@/swagger';

export const fastify = Fastify({
  logger: {
    level: 'debug',
    transport: {
      target: 'pino-pretty',
      options: {
        colorize: true,
        translateTime: 'HH:MM:ss Z',
        ignore: 'pid,hostname',
      },
    },
  },
});

const closeListeners = closeWithGrace({ delay: 500 }, async (opts: any) => {
  if (opts.err) {
    fastify.log.error(opts.err);
  }
  await fastify.close();
});
fastify.addHook('onClose', (_instance, done) => {
  closeListeners.uninstall();
  done();
});

const start = async () => {
  // Swagger must come before the app routes
  await initSwagger(fastify);
  await fastify.register(app);
  fastify.listen({ port: Number(process.env.PORT) || 8080, host: '0.0.0.0' }, (error) => {
    if (error) {
      fastify.log.error(error);
      process.exit(1);
    }
    fastify.log.info(
      'All routes loaded! Check your console for the route details.'
    );
    for (const route of fastify.printRoutes().split('\n')) {
      fastify.log.info(route);
    }
    fastify.log.info(`⚛️  Server running on port ${process.env.PORT || 8080}`);
  });
};
start();
