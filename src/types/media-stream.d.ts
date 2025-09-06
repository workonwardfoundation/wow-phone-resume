import { SupportedLanguage } from '@/types';
import { WebSocket } from 'ws';

export interface LogEntry {
  timestamp: string;
  role: 'User' | 'AI_Agent';
  text: string;
}

export interface Session {
  streamSid: string;
  phoneNumber: string;
  language: SupportedLanguage;
  latestMediaTimestamp: number;
  lastAudioDeltaTime: number;
  lastAssistantItem?: string | null;
  markQueue: string[];
  responseStartTimestampTwilio?: number | null;
  conversationLog: LogEntry[];
  audioWatchdog?: NodeJS.Timeout | null;
  openAiWs?: WebSocket | null;
}
