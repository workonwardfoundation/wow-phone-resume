import { Schema, model } from 'mongoose';

const transcriptSchema = new Schema({
  timestamp: { type: String, required: true },
  role: { type: String, enum: ['AI_Agent', 'User'], required: true },
  text: { type: String },
});
const TranscriptSchema = new Schema(
  {
    phone_number: { type: String, required: true },
    stream_id: { type: String, required: true },
    transcript: { type: [transcriptSchema] },
  },
  {
    versionKey: false,
    timestamps: true,
  }
);

const Transcripts = model('Transcripts', TranscriptSchema, 'Transcripts');
export default Transcripts;
