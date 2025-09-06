// src/controllers/callController.js
// import { getSystemMessage } from '../utils/helpers.js';

import { SupportedLanguage } from '@/types';
/**
 * Generates TwiML response for an incoming call.
 * @param {string} phoneNumber - Caller phone number.
 * @returns {string} - The XML response.
 */
export function handleIncomingCall() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Gather numDigits="1" action="/api/v1/call/language" method="POST">
    <Say language="en-US">Welcome to the WorkOnward Resume Assistant.</Say>
    <Pause length="1"/>
    <Say language="en-US">Please be aware that calls on this number are monitored, and the AI assistant may occasionally make mistakes.</Say>
    <Pause length="1"/>
    <Say language="en-US">For English, press 1.</Say>
    <Pause length="1"/>
    <Say language="es-ES">Para Español, presione 2.</Say>
    <Pause length="1"/>
    <Say language="zh-CN">中文服务，请按 3.</Say>
    <Pause length="1"/>
    <Say language="ru-RU">Для русского языка нажмите 4.</Say>
    <Pause length="1"/>
    <Say language="fr-CA">Pou kreyòl ayisyen, peze 5.</Say>
    <Pause length="1"/>
    <Say language="ko-KR">한국어를 원하시면 6을 누르세요.</Say>
  </Gather>
  <Say>We did not receive any input. Goodbye!</Say>
</Response>`;
}

/**
 * Handles language selection and generates a TwiML response.
 * @param {string} digits - The DTMF input.
 * @param {string} phoneNumber - Caller phone number.
 * @param {string} host - The request host to dynamically build the WebSocket URL.
 * @returns {string} - The XML response.
 */
export function handleLanguageSelection(
  digits: string,
  phoneNumber: string,
  host: string
) {
  let language: SupportedLanguage = 'en';
  let greeting = '';

  switch (digits) {
    case '1':
      language = 'en';
      greeting =
        "Hello, we will now begin the conversation in English. Let's begin with your full name.";
      break;
    case '2':
      language = 'es';
      greeting =
        'Hola, bienvenido a WorkOnward Resume Assistant. Ahora comenzaremos la conversación en español.';
      break;
    case '3':
      language = 'zh';
      greeting =
        '您好，欢迎使用 WorkOnward 简历助手。我们现在开始使用中文进行对话。';
      break;
    case '4':
      language = 'ru';
      greeting =
        'Здравствуйте, добро пожаловать в помощник по резюме WorkOnward. Теперь мы начнем разговор на русском языке.';
      break;
    case '5':
      language = 'ht';
      greeting =
        'Bonjou, byenveni nan Asistan Rezime WorkOnward. Koulye a, n ap kòmanse konvèsasyon an an kreyòl ayisyen.';
      break;
    case '6':
      language = 'ko';
      greeting =
        '안녕하세요, WorkOnward 이력서 도우미에 오신 것을 환영합니다. 이제 한국어로 대화를 시작하겠습니다.';
      break;
    default:
      language = 'en';
      greeting =
        "Hello, we will now begin the conversation in English. Let's begin with your full name.";
      break;
  }

  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="${
    language === 'es'
      ? 'es-ES'
      : language === 'zh'
        ? 'zh-CN'
        : language === 'ru'
          ? 'ru-RU'
          : language === 'ht'
            ? 'fr-CA'
            : language === 'ko'
              ? 'ko-KR'
              : 'en-US'
  }">${greeting}</Say>
  <Connect>
    <Stream url="wss://${host}/api/v1/media-stream">
      <Parameter name="phoneNumber" value="${phoneNumber}"/>
      <Parameter name="language" value="${language}"/>
    </Stream>
  </Connect>
</Response>`;
}
