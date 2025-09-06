import { Session } from '@/types/media-stream';
import Transcripts from '@/collections/transcript';
import { fastify } from '@/server';
import { Types } from 'mongoose';

class Controller {
  async create(session: Session): Promise<{ status: boolean; id?: Types.ObjectId }> {
    if (
      !session ||
      !session.conversationLog ||
      session.conversationLog.length === 0
    ) {
      fastify.log.info('No conversation data to save');
      return { status: false };
    }
    try {
      const created = await Transcripts.create({
        phone_number: session.phoneNumber || 'Unknown',
        stream_id: session.streamSid,
        transcript: session.conversationLog,
      });
      fastify.log.info(
        `Successfully saved conversation to MongoDB with ID: ${created._id}`
      );
      return { status: true, id: created._id };
    } catch (error) {
      fastify.log.error('Error saving conversation to MongoDB:', error);
      return { status: false };
    }
  }

}
const TranscriptsController = new Controller();
export default TranscriptsController;
