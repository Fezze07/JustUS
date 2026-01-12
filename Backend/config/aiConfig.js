const axios = require("axios");

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

async function generateAIQuestion(tipo) {
    const prompt = `
    Rispondi SOLO con JSON valido.
    Formato ESATTO:
    {"question":"TESTO DELLA DOMANDA?"}
    Regole:
    - Un solo campo: question
    - Deve iniziare con: ${tipo}
    - Domanda per una coppia (Fede e Claretta)
    - NON fare domande a cui non si puo rispondere con Fede o Claretta
    - NON scrivere mai i 3 puntini a fine frase, usa il punto di domanda = ?
    - NIENTE spiegazioni
    - NIENTE testo fuori dal JSON
    `;
    const r = await axios.post(
        "http://localhost:11434/api/generate",
        { model: "llama3.2:3b", prompt, temperature: 0.9 },
        { responseType: "stream" }
    );
    return new Promise((resolve, reject) => {
        let jsonText = "";
        r.data.on("data", chunk => {
            try {
                const obj = JSON.parse(chunk.toString());
                if (obj.response) {
                    jsonText += obj.response;
                }
            } catch {
            }
        });
        r.data.on("end", () => {
            jsonText = jsonText.trim().replace(/^`+|`+$/g, "");
            try {
                const json = JSON.parse(jsonText);
                resolve(json);
            } catch (e) {
                console.error("[AI] Errore parsing JSON finale:", e, "Testo:", jsonText);
                reject(e);
            }
        });
        r.data.on("error", err => {
            console.error("[AI] Errore stream:", err);
            reject(err);
        });
    });
}

module.exports = { tipiDomanda, generateAIQuestion };