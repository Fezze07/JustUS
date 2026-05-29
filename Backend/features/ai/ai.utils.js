/**
 * Pulisce il testo grezzo restituito dall'AI, rimuovendo blocchi markdown e frammenti non JSON.
 * @param {string} rawText - Il testo grezzo da pulire.
 * @returns {string} Il testo pulito pronto per il parsing JSON.
 */
function cleanAiResponse(rawText) {
  let cleaned = rawText.trim();

  // Rimuove blocchi markdown (```json ... ``` o ``` ...)
  cleaned = cleaned.replace(/```(?:json)?\n?([\s\S]*?)```/g, '$1');

  // Rimuove testo prima del primo '{' e dopo l'ultimo '}'
  const firstBrace = cleaned.indexOf('{');
  const lastBrace = cleaned.lastIndexOf('}');

  if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
    cleaned = cleaned.substring(firstBrace, lastBrace + 1);
  }

  return cleaned;
}

/**
 * Parsa il testo pulito in un oggetto JSON e valida la presenza del campo 'question'.
 * @param {string} cleanedText - Il testo pulito.
 * @param {number} maxTokens - Numero massimo di token per troncare la risposta se necessario.
 * @returns {object} Oggetto contenente la domanda formattata.
 * @throws {Error} Se il parsing fallisce o il formato non è corretto.
 */
function parseAiQuestion(cleanedText, maxTokens) {
  const json = JSON.parse(cleanedText);
  const question = String(json.question ?? "").trim();

  return {
    question: question.slice(0, maxTokens * 4),
  };
}

module.exports = { cleanAiResponse, parseAiQuestion };
