import { LogEntry, Session } from '@/types/media-stream';

import { FastifyRequest } from 'fastify';
import TranscriptsController from '@/controllers/transcript';
// src/controllers/mediaStreamController.js
import WebSocket from 'ws';
import { fastify } from '@/server';
import { getSystemMessage } from '@/utils/helpers';
import twilio from 'twilio';

// Validate required environment variables
const requiredEnvVars = {
  TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID,
  TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN,
  TWILIO_PHONE_NUMBER: process.env.TWILIO_PHONE_NUMBER,
  OPENAI_API_KEY: process.env.OPENAI_API_KEY,
  OPENAI_REALTIME_MODEL: process.env.OPENAI_REALTIME_MODEL
};

// Check for missing environment variables
const missingVars = Object.entries(requiredEnvVars)
  .filter(([_, value]) => !value)
  .map(([key, _]) => key);

if (missingVars.length > 0) {
  console.warn(`Warning: Missing environment variables: ${missingVars.join(', ')}`);
  console.warn('Some features may not work correctly. Please set these variables in Railway.');
}

const twilioClient = process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN 
  ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
  : null;

const NOT_ALLOWED_TOPICS = [
  'politics',
  'religion',
  'hate speech',
  'adult content',
  'self-harm',
  'violence',
  'drugs',
  'extremism',
];
const TOPIC_BLOCK_MESSAGE =
  "I'm sorry, but I cannot discuss that topic. Let's stay focused on resume assistance.";

// Configuration
const SHOW_TIMING_MATH = false; // Enable to show detailed timing logs

function isTopicAllowed(text?: string): boolean {
  if (!text) return true;
  const lowerText = text.toLowerCase();
  return !NOT_ALLOWED_TOPICS.some((topic) => lowerText.includes(topic));
}

// Global sessions map to track active streams.
const sessions = new Map<string, Session>();

/**
 * Handles speech started events for interrupt handling/AI preemption
 * Truncates the current AI response when user starts speaking
 */
function handleSpeechStartedEvent(session: Session, connection: WebSocket.WebSocket) {
  if (session.markQueue.length > 0 && session.responseStartTimestampTwilio != null) {
    const elapsedTime = session.latestMediaTimestamp - session.responseStartTimestampTwilio;
    if (SHOW_TIMING_MATH) {
      fastify.log.info(`Calculating elapsed time for truncation: ${session.latestMediaTimestamp} - ${session.responseStartTimestampTwilio} = ${elapsedTime}ms`);
    }

    if (session.lastAssistantItem) {
      const truncateEvent = {
        type: 'conversation.item.truncate',
        item_id: session.lastAssistantItem,
        content_index: 0,
        audio_end_ms: elapsedTime
      };
      if (SHOW_TIMING_MATH) {
        fastify.log.info('Sending truncation event:', truncateEvent);
      }
      
      if (session.openAiWs && session.openAiWs.readyState === WebSocket.OPEN) {
        session.openAiWs.send(JSON.stringify(truncateEvent));
      }
    }

    // Clear Twilio Media Streams buffer
    connection.send(JSON.stringify({
      event: 'clear',
      streamSid: session.streamSid
    }));

    // Reset session markers for interruption
    session.markQueue = [];
    session.lastAssistantItem = null;
    session.responseStartTimestampTwilio = null;
    
    fastify.log.info(`Interruption handled for stream ${session.streamSid}`);
  }
}

/**
 * Sends an initial greeting from the AI when the session starts
 * Uncomment the call to this function in the openAiWs.on('open') handler to enable
 */
function sendInitialGreeting(session: Session) {
  if (!session.openAiWs || session.openAiWs.readyState !== WebSocket.OPEN) return;
  
  const initialConversationItem = {
    type: 'conversation.item.create',
    item: {
      type: 'message',
      role: 'user',
      content: [
        {
          type: 'input_text',
          text: 'Greet the user with a welcome message and introduce yourself as an AI assistant powered by Twilio and OpenAI.'
        }
      ]
    }
  };
  
  if (SHOW_TIMING_MATH) {
    fastify.log.info('Sending initial conversation item:', initialConversationItem);
  }
  session.openAiWs.send(JSON.stringify(initialConversationItem));
  session.openAiWs.send(JSON.stringify({ type: 'response.create' }));
  
  fastify.log.info(`Sent initial greeting for stream ${session.streamSid}`);
}

export function handleMediaStream(
  connection: WebSocket.WebSocket,
  _: FastifyRequest
) {
  fastify.log.info('New WebSocket client connected');
  let streamSid: string | null = null;

  connection.on('message', (message) => {
    try {
      const data = JSON.parse(message as any);
      switch (data.event) {
        case 'start': {
          streamSid = data.start.streamSid;
          const phoneNumber =
            data.start.customParameters?.phoneNumber || 'Unknown';
          const chosenLanguage = data.start.customParameters?.language || 'en';
          fastify.log.info(
            `New call stream started - SID: ${streamSid}, Phone: ${phoneNumber}, Language: ${chosenLanguage}`
          );
          if (!streamSid) throw new Error('Missing streamSid');
          // Initialize session
          sessions.set(streamSid, {
            streamSid,
            phoneNumber,
            language: chosenLanguage,
            latestMediaTimestamp: 0,
            lastAudioDeltaTime: Date.now(),
            lastAssistantItem: null,
            markQueue: [],
            responseStartTimestampTwilio: null,
            conversationLog: [],
            audioWatchdog: null,
            openAiWs: null,
          });
          const session = sessions.get(streamSid);
          if (!session) throw new Error("Session wasn't initialized");
          // Setup watchdog for missing audio delta messages.
          session.audioWatchdog = setInterval(() => {
            const now = Date.now();
            if (now - session.lastAudioDeltaTime > 5000) {
              fastify.log.info(
                `Audio watchdog: No audio delta received for session ${streamSid} in over 5 seconds.`
              );
              if (
                session.openAiWs &&
                session.openAiWs.readyState === WebSocket.OPEN
              ) {
                const systemMessage = getSystemMessage(session.language);
                const sessionUpdate = {
                  type: 'session.update',
                  session: {
                    turn_detection: {
                      type: 'server_vad',
                    },
                    input_audio_format: 'g711_ulaw',
                    output_audio_format: 'g711_ulaw',
                    voice: 'alloy',
                    instructions: systemMessage,
                    modalities: ['text', 'audio'],
                    temperature: 0.7,
                    input_audio_transcription: {
                      model: 'whisper-1',
                    },
                  },
                };
                session.openAiWs.send(JSON.stringify(sessionUpdate));
              }
            }
          }, 2000);

          // Connect to OpenAI Realtime WebSocket
          const websocketUrl = `wss://api.openai.com/v1/realtime?model=${process.env.OPENAI_REALTIME_MODEL}`;
          fastify.log.info(`Attempting to connect to OpenAI WebSocket: ${websocketUrl}`);
          
          let openAiWs: WebSocket;
          try {
            openAiWs = new WebSocket(
              websocketUrl,
              {
                headers: {
                  Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
                  'OpenAI-Beta': 'realtime=v1',
                },
              }
            );
            session.openAiWs = openAiWs;
            
            
          } catch (connectionError) {
            fastify.log.error(`Failed to create WebSocket instance for stream ${streamSid}:`, {
              error: connectionError,
              message: (connectionError as Error).message,
              stack: (connectionError as Error).stack
            });
            return; // Exit early if we can't even create the WebSocket
          }

          openAiWs.on('open', () => {
            fastify.log.info(
              `Connected to OpenAI for stream ${streamSid}`
            );
            const systemMessage = getSystemMessage(session.language);
            const sessionUpdate = {
              type: 'session.update',
              session: {
                turn_detection: {
                  type: 'server_vad',
                },
                input_audio_format: 'g711_ulaw',
                output_audio_format: 'g711_ulaw',
                voice: 'alloy',
                instructions: systemMessage,
                modalities: ['text', 'audio'],
                temperature: 0.7,
                input_audio_transcription: {
                  model: 'whisper-1',
                },
              },
            };
            
            fastify.log.info(`Sending session configuration for stream ${streamSid}:`);
            
            try {
              const configJson = JSON.stringify(sessionUpdate, null, 2);
              fastify.log.info(`Session config JSON: ${configJson}`);
              openAiWs.send(configJson);
              fastify.log.info('Session config successfully sent to OpenAI');
            } catch (error) {
              fastify.log.error('Error sending session config:', error);
              fastify.log.info('Raw sessionUpdate object:', sessionUpdate);
            }
            
            // Uncomment this line to have the AI speak first
            // setTimeout(() => sendInitialGreeting(session), 500);
          });

          openAiWs.on('message', (data) => {
            try {
              const response = JSON.parse(data as any);
              if (!streamSid || !sessions.has(streamSid)) return;
              const session = sessions.get(streamSid);
              if (!session) return;
              
              // Handle speech started event for interruption
              if (response.type === 'input_audio_buffer.speech_started') {
                fastify.log.info(`Speech started detected for stream ${streamSid}`);
                handleSpeechStartedEvent(session, connection);
              }
              
              // Process audio delta responses.
              if (response.type === 'response.audio.delta' && response.delta) {
                session.lastAudioDeltaTime = Date.now();
                connection.send(
                  JSON.stringify({
                    event: 'media',
                    streamSid: session.streamSid,
                    media: {
                      payload: response.delta,
                    },
                  })
                );
                if (!session.responseStartTimestampTwilio) {
                  session.responseStartTimestampTwilio =
                    session.latestMediaTimestamp;
                  if (SHOW_TIMING_MATH) {
                    fastify.log.info(`Setting start timestamp for new response: ${session.responseStartTimestampTwilio}ms`);
                  }
                }
                if (response.item_id)
                  session.lastAssistantItem = response.item_id;
                connection.send(
                  JSON.stringify({
                    event: 'mark',
                    streamSid: session.streamSid,
                    mark: {
                      name: 'responsePart',
                    },
                  })
                );
                session.markQueue.push('responsePart');
              }

              // Process user transcription.
              if (
                response.type ===
                'conversation.item.input_audio_transcription.completed'
              ) {
                let transcript = response.transcript;
                if (!isTopicAllowed(transcript)) {
                  fastify.log.info(
                    `User transcript contains disallowed topic: "${transcript}"`
                  );
                  transcript = TOPIC_BLOCK_MESSAGE;
                }
                const timestamp = new Date().toISOString();
                const logEntry: LogEntry = {
                  timestamp,
                  role: 'User',
                  text: transcript,
                };
                fastify.log.info(`[${streamSid}] User: ${transcript}`);
                session.conversationLog.push(logEntry);
              }

              // Process AI transcription.
              if (response.type === 'response.audio_transcript.done') {
                let transcript = response.transcript;
                if (!isTopicAllowed(transcript)) {
                  fastify.log.info(
                    `AI transcript contains disallowed topic: "${transcript}"`
                  );
                  transcript = TOPIC_BLOCK_MESSAGE;
                }
                const timestamp = new Date().toISOString();
                const logEntry: LogEntry = {
                  timestamp,
                  role: 'AI_Agent',
                  text: transcript,
                };
                fastify.log.info(`[${streamSid}] AI: ${transcript}`);
                session.conversationLog.push(logEntry);

                // Check for goodbye message to disconnect.
                if (transcript.toLowerCase().includes('goodbye')) {
                  fastify.log.info(
                    `Goodbye detected for stream ${streamSid}. Initiating disconnect sequence.`
                  );
                  connection.send(
                    JSON.stringify({
                      event: 'disconnect',
                      streamSid: session.streamSid,
                      message:
                        'Conversation ended. Disconnecting call in 3 seconds',
                    })
                  );
                  setTimeout(() => {
                    connection.close();
                  }, 17000);
                  return;
                }
              }
            } catch (error) {
              fastify.log.error(
                `Error processing OpenAI message for stream ${streamSid || 'unknown'
                }:`,
                error
              );
            }
          });

          openAiWs.on('close', (code, reason) => {
            fastify.log.info(
              `Disconnected from OpenAI for stream ${streamSid}`,
              {
                closeCode: code,
                closeReason: reason?.toString(),
                timestamp: new Date().toISOString()
              }
            );
          });

          openAiWs.on('error', (error) => {
            fastify.log.error(
              `OpenAI WebSocket error for stream ${streamSid}:`,
              {
                message: error.message,
                name: error.name,
                code: (error as any).code,
                type: (error as any).type,
                stack: error.stack,
                stringified: JSON.stringify(error),
                fullError: error,
                errorKeys: Object.keys(error)
              }
            );
          });
          break;
        }
        case 'media': {
          if (!streamSid || !sessions.has(streamSid)) break;
          const session = sessions.get(streamSid);
          if (!session) break;
          session.latestMediaTimestamp = data.media.timestamp;
          if (SHOW_TIMING_MATH) {
            fastify.log.info(`Received media message with timestamp: ${session.latestMediaTimestamp}ms`);
          }
          if (
            session.openAiWs &&
            session.openAiWs.readyState === WebSocket.OPEN
          ) {
            session.openAiWs.send(
              JSON.stringify({
                type: 'input_audio_buffer.append',
                audio: data.media.payload,
              })
            );
          }
          break;
        }
        case 'mark': {
          if (!streamSid || !sessions.has(streamSid)) break;
          const session = sessions.get(streamSid);
          if (!session) break;
          if (session.markQueue.length > 0) session.markQueue.shift();
          break;
        }
        default:
          fastify.log.info(`Received non-media event: ${data.event}`);
          break;
      }
    } catch (error) {
      fastify.log.error(
        `Error parsing WebSocket message for stream ${streamSid || 'unknown'}:`,
        error
      );
    }
  });

  connection.on('close', async () => {
    try {
      if (!streamSid || !sessions.has(streamSid)) {
        fastify.log.info(
          'Connection closed for unknown or already closed session'
        );
        return;
      }
      const session = sessions.get(streamSid);
      if (!session) throw new Error("Session wasn't initialized");
      fastify.log.info(
        `WebSocket connection closing for stream ${streamSid} with ${session.conversationLog.length} messages`
      );

      if (session.openAiWs?.readyState === WebSocket.OPEN) {
        session.openAiWs.close();
        fastify.log.info(`Closed OpenAI WebSocket for stream ${streamSid}`);
      }
      if (session.audioWatchdog) {
        clearInterval(session.audioWatchdog);
      }
      if (session.conversationLog && session.conversationLog.length > 0) {
        fastify.log.info(
          `Saving conversation with ${session.conversationLog.length} messages to MongoDB...`
        );
        const saved = await TranscriptsController.create(session);
        if (saved.status) {
          fastify.log.info(
            `Successfully saved conversation for stream ${streamSid}`
          );

          // Send a message after the call ends
          const message = `Hi! Thanks for the call. You can access your resume powered by WorkOnward AI using this link. 
          https://resume.workonward.org/sign-up?id=${saved.id}`;
          
          if (twilioClient) {
            try {
              const response = await twilioClient.messages.create({
                body: message,
                from: process.env.TWILIO_PHONE_NUMBER,
                to: session.phoneNumber,
              });
              fastify.log.info(
                `Message sent to ${session.phoneNumber}: SID ${response.sid}`
              );
            } catch (error) {
              fastify.log.error(
                `Failed to send message to ${session.phoneNumber}:`,
                error
              );
            }
          } else {
            fastify.log.warn('Twilio client not initialized, skipping message send');
          }
        } else {
          fastify.log.error(
            `Failed to save conversation for stream ${streamSid}`
          );
        }
      } else {
        fastify.log.info(
          `No conversation data to save for stream ${streamSid}`
        );
      }

      sessions.delete(streamSid);
      fastify.log.info(
        `Session ${streamSid} cleaned up and removed from active sessions`
      );
    } catch (e) {
      fastify.log.error(e);
      throw e;
    }
  });
}
