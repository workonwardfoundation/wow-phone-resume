import type { FastifyInstance } from 'fastify';

import fastifySwagger from '@fastify/swagger';
import fastifySwaggerUi from '@fastify/swagger-ui';

// Swagger definition
// https://github.com/swagger-api/swagger-spec/blob/master/versions/2.0.md
export async function initSwagger(app: FastifyInstance) {
  try {
    if (process.env.NODE_ENV === 'production') return;
    await app.register(fastifySwagger, {
      mode: 'dynamic',
      openapi: {
        openapi: '3.0.0',
        info: {
          title: 'Backend',
          version: '0.0.1',
          description: 'Call based resume backend',
        },
        tags: [
          { name: 'Health', description: 'Health related code' },
          // { name: 'code', description: 'Code related end-points' },
        ],
        externalDocs: {
          url: 'https://swagger.io',
          description: 'Find more info here',
        },
      },
      // prefix: '/api/v1',
    });
    await app.register(fastifySwaggerUi, {
      routePrefix: '/docs',
      uiConfig: {
        docExpansion: 'full',
        deepLinking: false,
      },
      uiHooks: {
        onRequest(request, reply, next) {
          next();
        },
        preHandler(request, reply, next) {
          next();
        },
      },
      staticCSP: true,
      transformStaticCSP: (header) => header,
    });
  } catch (e) {
    app.log.error(e);
  }
}
