const axios = require("axios");
const { env, cleanAiResponse, parseAiQuestion, logError } = require("../all_imports");

const tipiDomanda = [
  "Chi è più propenso a…","Chi è più bravo a…","Chi è più disordinato…","Chi impiega più tempo a…",
  "Chi è più socievole…","Chi dimentica più spesso…","Chi è più romantico…","Chi prende più iniziativa…",
  "Chi ride di più alle battute stupide…","Chi si arrabbia più facilmente…","Chi ha più pazienza…","Chi cucina meglio…",
  "Chi si perde più facilmente…","Chi ha più inventiva…","Chi è più competitivo…","Chi è più geloso…",
  "Chi è più impulsivo…","Chi è più organizzato…","Chi fa più sorprese…","Chi si distrae più facilmente…",
  "Chi dorme di più…","Chi parla di più…","Chi è più prudente…","Chi spende di più…",
  "Chi perde più tempo sul telefono…","Chi propone più uscite…","Chi è più puntuale…","Chi tende a rimandare di più…",
  "Chi è più creativo…","Chi è più testardo…","Chi è più sensibile…","Chi è più energico…",
  "Chi si annoia più facilmente…","Chi ha più fantasia…","Chi è più curioso…","Chi si addormenta prima…",
  "Chi sopporta meno il caldo…","Chi sopporta meno il freddo…","Chi è più permaloso…","Quale dei due tende a…",
  "Quale dei due preferisce…","Quale dei due sarebbe capace di…","Quale dei due inizierebbe per primo a…","Quale dei due farebbe una figuraccia mentre…",
  "Quale dei due si ricorderebbe per primo di…","Quale dei due avrebbe più voglia di…","Quale dei due si lamenterebbe per…","Quale dei due reagirebbe peggio a…",
  "Quale dei due riderebbe per…","Quale dei due sarebbe più felice di…","Tra voi due, chi sarebbe più adatto a…","Tra voi due, chi finirebbe per…",
  "Tra voi due, chi reagirebbe meglio a…","Tra voi due, chi avrebbe l’idea di…","Tra voi due, chi crollerebbe prima durante…","Tra voi due, chi si emozionerebbe di più per…",
  "Tra voi due, chi combinerebbe un casino se…","Chi dei due scoppierebbe a ridere mentre…","Chi dei due farebbe una scelta assurda mentre…","Chi dei due diventerebbe super competitivo quando…",
  "Chi dei due si prenderebbe troppo sul serio quando…","Chi dei due chiederebbe aiuto prima se…","Chi dei due si arrenderebbe subito se…","Chi dei due inventerebbe una scusa per evitare…"
];

function estimateTokenCount(text) {
    return Math.max(1, Math.ceil((text ?? "").length / 4));
}

const MODELS = [
  "openrouter/free",
  "openai/gpt-oss-120b:free",
  "nvidia/nemotron-3-super:free"
];

async function generateAIQuestion(tipo) {
    const messages = buildAiPrompt(tipo);
    const apiKey = process.env.OPENROUTER_API_KEY;
    const url = "https://openrouter.ai/api/v1/chat/completions";

    let lastError = null;

    for (const model of MODELS) {
        try {
            const response = await axios.post(
                url,
                {
                    model: model,
                    messages,
                },
                {
                    headers: {
                        "Content-Type": "application/json",
                        Authorization: `Bearer ${apiKey || ""}`
                    },
                    timeout: env.aiTimeoutMs || 12000
                }
            );

            const content = response.data?.choices?.[0]?.message?.content;
            if (!content) {
                throw new Error(`Empty response content from model ${model}`);
            }

            const cleaned = cleanAiResponse(content);
            const parsed = parseAiQuestion(cleaned, env.aiMaxTokens || 160);
            return parsed;
        } catch (error) {
            lastError = error;
            logError({
                error: {
                    message: error.message,
                    name: error.name,
                    status: error.response?.status,
                    data: error.response?.data
                },
                event: "ai.model_failed",
                model: model
            });
        }
    }

    throw lastError || new Error("All AI models failed");
}

/**
 * Costruisce il prompt per l'AI.
 * @param {string} tipo - Il tipo di domanda da generare.
 * @param {object} partnerNames - I nomi dei partner.
 * @returns {string} Il prompt formattato.
 */
function buildAiPrompt(tipo) {
  return [
    {
      role: "system",
      content: `Genera una domanda divertente per una coppia.
Regole:
- Rispondi SOLO con JSON valido: {"question":"TESTO DELLA DOMANDA?"}
- La domanda deve iniziare ESATTAMENTE con il tipo fornito.
- Deve avere senso grammaticale in italiano.
- NON usare i 3 puntini (...), usa sempre ?.
- NON inserire nomi di persone nella domanda.
- NIENTE spiegazioni, niente testo fuori dal JSON.

Esempio:
Input: "Chi è più romantico…"
Output: {"question":"Chi è più romantico tra i due?"}`
    },
    {
      role: "user",
      content: tipo
    }
  ];
}

module.exports = { tipiDomanda, generateAIQuestion, estimateTokenCount };
