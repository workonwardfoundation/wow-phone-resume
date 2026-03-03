import {
  FastifyInstance,
  FastifyPluginOptions,
  HookHandlerDoneFunction,
} from 'fastify';

export const autoPrefix = '/health';
export default function healthRoutes(
  fastify: FastifyInstance,
  _: FastifyPluginOptions,
  done: HookHandlerDoneFunction
) {
  fastify.get('/', async (request, reply) => {
    reply.send({ status: 'healthy', timestamp: new Date().toISOString() });
  });

  fastify.get('/health', async (request, reply) => {
    const envCheck = {
      DB_URL: !!process.env.DB_URL,
      TWILIO_ACCOUNT_SID: !!process.env.TWILIO_ACCOUNT_SID,
      TWILIO_AUTH_TOKEN: !!process.env.TWILIO_AUTH_TOKEN,
      TWILIO_PHONE_NUMBER: !!process.env.TWILIO_PHONE_NUMBER,
      OPENAI_API_KEY: !!process.env.OPENAI_API_KEY,
      OPENAI_REALTIME_MODEL: !!process.env.OPENAI_REALTIME_MODEL,
      PORT: process.env.PORT || '8080',
      NODE_ENV: process.env.NODE_ENV || 'development'
    };

    const missingVars = Object.entries(envCheck)
      .filter(([key, value]) => key !== 'PORT' && key !== 'NODE_ENV' && !value)
      .map(([key]) => key);

    reply.send({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      environment: envCheck,
      missing_variables: missingVars,
      has_missing_vars: missingVars.length > 0
    });
  });

  done();
}
