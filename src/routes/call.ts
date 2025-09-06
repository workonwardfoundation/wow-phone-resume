import {
  FastifyInstance,
  FastifyPluginOptions,
  HookHandlerDoneFunction,
} from 'fastify';
import {
  handleIncomingCall,
  handleLanguageSelection,
} from '@/controllers/call';

export const autoPrefix = '/call';

export default function callRoutes(
  fastify: FastifyInstance,
  _: FastifyPluginOptions,
  done: HookHandlerDoneFunction
) {
  fastify.post('/incoming', async (request, reply) => {
    try {
      fastify.log.info('Received incoming call webhook', {
        body: request.body,
        headers: request.headers,
        query: request.query
      });

      const phoneNumber: any =
        request.body?.From ||
        request.query?.From ||
        request.headers['x-twilio-from'] ||
        'Unknown';
      
      fastify.log.info(`Processing incoming call from: ${phoneNumber}`);
      
      const response = handleIncomingCall();
      fastify.log.info('Sending TwiML response for incoming call');
      
      reply.type('text/xml').send(response);
    } catch (error) {
      fastify.log.error('Error handling incoming call:', error);
      reply.status(500).send('Internal Server Error');
    }
  });

  fastify.post('/language', async (request, reply) => {
    try {
      fastify.log.info('Received language selection webhook', {
        body: request.body,
        headers: request.headers,
        query: request.query
      });

      const body = request.body as {
        Digits?: string;
        From?: string;
      };
      const query = request.query as {
        Digits?: string;
        From?: string;
      };
      const digits = body?.Digits || query?.Digits || '';
      const phoneNumber = body?.From || query?.From || 'Unknown';
      const host = request.headers.host || "wow-phone-resume-production.up.railway.app";
      
      fastify.log.info(`Processing language selection: digits=${digits}, phone=${phoneNumber}, host=${host}`);
      
      const response = handleLanguageSelection(
        digits,
        phoneNumber,
        host as string
      );
      
      fastify.log.info('Sending TwiML response for language selection');
      reply.type('text/xml').send(response);
    } catch (error) {
      fastify.log.error('Error handling language selection:', error);
      reply.status(500).send('Internal Server Error');
    }
  });
  done();
}
