# JustUs 💖

![JustUs](JustUs.png)

**JustUs** è un applicazione digitale progettata per le coppie, composta da un'applicazione Android nativa e un backend Node.js. Permette di condividere emozioni, gestire file in uno spazio comune, completare una bucket list di coppia e sfidarsi in mini-giochi quotidiani.

---

## ✨ Funzionalità Principali

### 🌈 Mood & Emotions
Condividi il tuo stato d'animo attuale con la tua metà attraverso emoji personalizzate. Visualizza il mood del partner in tempo reale sulla home.

### 💓 Miss You
Un sistema rapido per inviare notifiche "Mi manchi". Un contatore tiene traccia di quante volte vi siete pensati!

### 📝 Bucket List
Una lista condivisa di obiettivi e sogni da realizzare insieme. Aggiungi nuovi traguardi e spunta quelli completati.

### 🎮 Couple Game
Ogni giorno una nuova sfida! Rispondi a domande su di te e scopri se il tuo partner conosce davvero i tuoi gusti. Include un sistema di notifiche per sollecitare la risposta del partner.

### 📂 Shared Drive
Uno spazio cloud riservato per caricare foto e video dei vostri momenti migliori. Supporta anteprime, gestione favoriti e download locale.

### 👤 Profile & Partner management
Personalizza il tuo profilo con avatar e gestisci il legame con il partner tramite un sistema di codici univoci.

---

## 🛠️ Stack Tecnologico

### **Backend** (Node.js)
- **Runtime**: Node.js con Express framework.
- **Database**: MySQL per la persistenza dei dati.
- **Auth**: JWT (JSON Web Tokens) per sessioni sicure.
- **Cloud Messaging**: Firebase Admin SDK per le notifiche push.
- **File Storage**: Gestione locale degli upload tramite Multer.

### **Frontend** (Android)
- **Linguaggio**: Kotlin.
- **UI**: XML con Material Design 3 e Jetpack Compose (per componenti moderni).
- **Network**: Retrofit + OkHttp.
- **Image Loading**: Glide.
- **Async**: Kotlin Coroutines.

---

## 📁 Struttura del Progetto

```text
App/
├── Backend/          # Server Node.js, API e gestione DB
├── Frontend/         # Progetto Android Studio (App)
└── JustUs.png        # Asset grafici
```

---

## 🚀 Guida al Setup

### 1. Backend & Database
1.  **Configurazione**: Crea un file `.env` in `Backend/config/` con le seguenti variabili:
    ```env
    DB_HOST=tuo_host
    DB_USER=root
    DB_PASSWORD=tua_password
    DB_NAME=justus_db
    DB_PORT=3306
    JWT_SECRET=una_chiave_molto_segreta
    ```
2.  **Avvio**:
    ```bash
    cd Backend
    npm install
    npm start
    ```

### 2. Frontend (Android)
1.  Apri la cartella `Frontend/` con **Android Studio**.
2.  Assicurati di avere il file `google-services.json` per Firebase.
3.  Configura il file `keystore.properties` per la firma dell'app.
4.  Modifica il `BASE_URL` in `app/build.gradle.kts` per puntare al tuo server (locale o remoto).
5.  Esegui il build e installa l'app sul tuo dispositivo.

---

## 🔔 Sistema di Aggiornamento
L'app include un sistema di auto-update integrato. Caricando un nuovo APK nella cartella `Backend/versions/apk` e aggiornando il file app_version.json, l'app notificherà automaticamente gli utenti della disponibilità di una nuova versione.

---

Federico Cisera