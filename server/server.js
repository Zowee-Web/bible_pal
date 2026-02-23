// server.js (CommonJS)
require("dotenv").config({ override: true });

const express = require("express");
const helmet = require("helmet");
const cors = require("cors");
const rateLimit = require("express-rate-limit");
const { Readable } = require("stream");
const fetch = require("node-fetch"); // v3 works with require in CJS if "type": "commonjs" is set

const app = express();
app.use(helmet());
app.use(cors());
app.use(express.urlencoded({ extended: true }));
app.use(express.json({ limit: "1mb" }));

const limiter = rateLimit({
  windowMs: 60_000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// === Config from .env ===
const apiKey = process.env.ELEVENLABS_API_KEY_TEST; // <-- USE TEST KEY
const defaultVoiceId = process.env.ELEVENLABS_VOICE_ID || "";
let voicesMap = {};
try {
  const raw = process.env.ELEVENLABS_VOICES_JSON || "";
  voicesMap = raw ? JSON.parse(raw) : {};
} catch {
  voicesMap = {};
}

// === Load voiceKey -> elevenLabsId mapping from voices.json ===
const voiceKeyMap = {};
try {
  const voicesData = require("./voices.json");
  for (const v of voicesData.voices || []) {
    if (v.voiceKey && v.elevenLabsId) {
      voiceKeyMap[v.voiceKey] = v.elevenLabsId;
    }
  }
  console.log(`Loaded ${Object.keys(voiceKeyMap).length} voice keys from voices.json`);
} catch (e) {
  console.warn("Could not load voices.json:", e.message);
}

function getVoiceId(byNameOrId) {
  if (!byNameOrId) return defaultVoiceId;
  // Check voiceKey map first (e.g., VOICE_SARAH_STORYTELLER)
  if (voiceKeyMap[byNameOrId]) return voiceKeyMap[byNameOrId];
  // if it's an exact id, pass through; else map name -> id
  if (byNameOrId.startsWith("voice_")) return byNameOrId;
  return voicesMap[byNameOrId] || defaultVoiceId;
}

// Quick env probe
app.get("/debug-env", (_req, res) => {
  res.json({
    PORT: process.env.PORT || "8080",
    ELEVENLABS_API_KEY_TEST: apiKey ? "LOADED" : "MISSING",
    ELEVENLABS_VOICE_ID: defaultVoiceId ? "SET" : "EMPTY",
    ELEVENLABS_VOICES_JSON: voicesMap && Object.keys(voicesMap).length
      ? { LOADED: true, keys: Object.keys(voicesMap).slice(0, 20) }
      : "EMPTY",
  });
});

// Normalize inputs (works for both GET query and POST form)
function readParams(req) {
  const isPost = req.method === "POST";
  const q = isPost ? req.body : req.query;
  return {
    voice: (q.voice || "").trim(),
    text: (q.text || "").toString(),
    useSsml: q.use_ssml === "1" || q.use_ssml === "true" || q.use_ssml === 1 || q.use_ssml === true,
    modelId: (q.model_id || "eleven_turbo_v2_5").trim(),
  };
}

// TTS route (GET and POST)
async function handleTTS(req, res) {
  try {
    if (!apiKey) {
      return res.status(500).json({ error: "missing_api_key_test" });
    }

    const { voice, text, useSsml, modelId } = readParams(req);
    if (!text) return res.status(400).json({ error: "missing_text" });

    const voiceId = getVoiceId(voice);
    if (!voiceId) return res.status(400).json({ error: "missing_voice_id" });

    const url = `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}/stream?optimize_streaming_latency=3`;

    const r = await fetch(url, {
      method: "POST",
      headers: {
        "xi-api-key": apiKey,
        "Content-Type": "application/json",
        Accept: "audio/mpeg",
      },
      body: JSON.stringify({
        model_id: modelId,
        // ElevenLabs accepts SSML if the model supports it; we just pass text as-is
        text,
        voice_settings: { stability: 0.4, similarity_boost: 0.8 },
        output_format: "mp3_44100_128",
        // optionally: "use_ssml": !!useSsml  (some SDKs use this flag; HTTP API mainly looks at the text content)
      }),
    });

    if (!r.ok) {
      const errTxt = await r.text().catch(() => "");
      console.error("ElevenLabs error", r.status, errTxt);
      return res.status(502).json({ error: "upstream_error", status: r.status, detail: errTxt });
    }

    res.setHeader("Content-Type", "audio/mpeg");
    Readable.fromWeb(r.body).pipe(res);
  } catch (e) {
    console.error("Server error:", e);
    if (!res.headersSent) res.status(500).json({ error: "server_error" });
  }
}

app.get("/tts", handleTTS);
app.post("/tts", handleTTS);

// === Name prefix TTS route (stricter validation + tighter rate limit) ===
const namePrefixLimiter = rateLimit({
  windowMs: 60_000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "rate_limited", detail: "Max 10 name-prefix requests per minute" },
});

app.post("/tts/name-prefix", namePrefixLimiter, async (req, res) => {
  const { voice, text } = req.body || {};

  // Validate voice: must be a known voiceKey
  if (!voice || !voiceKeyMap[voice]) {
    return res.status(400).json({ error: "invalid_voice", detail: "voice must be a valid voiceKey" });
  }

  // Validate text: required, trimmed, max 80 chars, no dangerous chars
  const trimmed = (text || "").toString().trim();
  if (!trimmed) {
    return res.status(400).json({ error: "invalid_text", detail: "text is required" });
  }
  if (trimmed.length > 80) {
    return res.status(400).json({ error: "invalid_text", detail: "text must be <= 80 characters" });
  }
  if (/[<>]/.test(trimmed)) {
    return res.status(400).json({ error: "invalid_text", detail: "text must not contain < or >" });
  }
  if (/\n|\r/.test(trimmed)) {
    return res.status(400).json({ error: "invalid_text", detail: "text must not contain newlines" });
  }
  if (/https?:\/\//i.test(trimmed)) {
    return res.status(400).json({ error: "invalid_text", detail: "text must not contain URLs" });
  }

  // Override body for handleTTS
  req.body = { voice, text: trimmed };
  return handleTTS(req, res);
});

const port = Number(process.env.PORT || 8080);
app.listen(port, "0.0.0.0", () => console.log(`Bible PAL proxy listening on :${port}`));
