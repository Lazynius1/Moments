#!/usr/bin/env node
/**
 * Upsert interests/ docs in Firestore (glowsy-6a40e).
 * Run: cd Moments && node scripts/seed-interests.mjs
 * Requires: firebase login (ADC) or GOOGLE_APPLICATION_CREDENTIALS
 */
import { createRequire } from "module";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(__dirname, "../functions/node_modules/firebase-admin/package.json"));
const admin = require("firebase-admin");

const PROJECT_ID = "glowsy-6a40e";
const INTERESTS = [
  {
    "id": "photography",
    "name": "Fotografía",
    "emoji": "📸",
    "order": 1
  },
  {
    "id": "travel",
    "name": "Viajes",
    "emoji": "✈️",
    "order": 2
  },
  {
    "id": "music",
    "name": "Música",
    "emoji": "🎵",
    "order": 3
  },
  {
    "id": "movies",
    "name": "Cine",
    "emoji": "🎬",
    "order": 4
  },
  {
    "id": "art",
    "name": "Arte",
    "emoji": "🎨",
    "order": 5
  },
  {
    "id": "sports",
    "name": "Deportes",
    "emoji": "⚽",
    "order": 6
  },
  {
    "id": "books",
    "name": "Libros",
    "emoji": "📚",
    "order": 7
  },
  {
    "id": "cooking",
    "name": "Cocina",
    "emoji": "👨‍🍳",
    "order": 8
  },
  {
    "id": "technology",
    "name": "Tecnología",
    "emoji": "💻",
    "order": 9
  },
  {
    "id": "fashion",
    "name": "Moda",
    "emoji": "👗",
    "order": 10
  },
  {
    "id": "gaming",
    "name": "Gaming",
    "emoji": "🎮",
    "order": 11
  },
  {
    "id": "fitness",
    "name": "Fitness",
    "emoji": "💪",
    "order": 12
  },
  {
    "id": "nature",
    "name": "Naturaleza",
    "emoji": "🌿",
    "order": 13
  },
  {
    "id": "animals",
    "name": "Animales",
    "emoji": "🐾",
    "order": 14
  },
  {
    "id": "food",
    "name": "Comida",
    "emoji": "🍽️",
    "order": 15
  },
  {
    "id": "science",
    "name": "Ciencia",
    "emoji": "🔬",
    "order": 16
  },
  {
    "id": "history",
    "name": "Historia",
    "emoji": "📜",
    "order": 17
  },
  {
    "id": "politics",
    "name": "Política",
    "emoji": "🏛️",
    "order": 18
  },
  {
    "id": "business",
    "name": "Negocios",
    "emoji": "💼",
    "order": 19
  },
  {
    "id": "health",
    "name": "Salud",
    "emoji": "❤️‍🩹",
    "order": 20
  },
  {
    "id": "style",
    "name": "Estilo",
    "emoji": "✨",
    "order": 21
  },
  {
    "id": "dance",
    "name": "Baile",
    "emoji": "💃",
    "order": 22
  },
  {
    "id": "writing",
    "name": "Escritura",
    "emoji": "✍️",
    "order": 23
  },
  {
    "id": "diy",
    "name": "DIY",
    "emoji": "🔧",
    "order": 24
  },
  {
    "id": "cars",
    "name": "Coches",
    "emoji": "🚗",
    "order": 25
  },
  {
    "id": "theater",
    "name": "Teatro",
    "emoji": "🎭",
    "order": 26
  },
  {
    "id": "meditation",
    "name": "Meditación",
    "emoji": "🕯️",
    "order": 27
  },
  {
    "id": "entrepreneurship",
    "name": "Emprendimiento",
    "emoji": "🚀",
    "order": 28
  },
  {
    "id": "yoga",
    "name": "Yoga",
    "emoji": "🧘",
    "order": 29
  },
  {
    "id": "coffee",
    "name": "Café",
    "emoji": "☕",
    "order": 30
  },
  {
    "id": "astronomy",
    "name": "Astronomía",
    "emoji": "⭐",
    "order": 31
  },
  {
    "id": "podcasts",
    "name": "Podcasts",
    "emoji": "🎧",
    "order": 32
  },
  {
    "id": "pets",
    "name": "Mascotas",
    "emoji": "🐶",
    "order": 33
  },
  {
    "id": "design",
    "name": "Diseño",
    "emoji": "🖌️",
    "order": 34
  },
  {
    "id": "programming",
    "name": "Programación",
    "emoji": "👩‍💻",
    "order": 35
  },
  {
    "id": "kpop",
    "name": "K-pop",
    "emoji": "🎤",
    "order": 36
  },
  {
    "id": "anime",
    "name": "Anime",
    "emoji": "🎌",
    "order": 37
  },
  {
    "id": "hiking",
    "name": "Senderismo",
    "emoji": "🥾",
    "order": 38
  },
  {
    "id": "cycling",
    "name": "Ciclismo",
    "emoji": "🚴",
    "order": 39
  },
  {
    "id": "running",
    "name": "Correr",
    "emoji": "🏃",
    "order": 40
  },
  {
    "id": "climbing",
    "name": "Escalada",
    "emoji": "🧗",
    "order": 41
  },
  {
    "id": "surfing",
    "name": "Surf",
    "emoji": "🏄",
    "order": 42
  },
  {
    "id": "football",
    "name": "Fútbol",
    "emoji": "⚽",
    "order": 43
  },
  {
    "id": "basketball",
    "name": "Baloncesto",
    "emoji": "🏀",
    "order": 44
  },
  {
    "id": "swimming",
    "name": "Natación",
    "emoji": "🏊",
    "order": 45
  },
  {
    "id": "skateboarding",
    "name": "Skate",
    "emoji": "🛹",
    "order": 46
  },
  {
    "id": "vinyl",
    "name": "Vinilos",
    "emoji": "💿",
    "order": 47
  },
  {
    "id": "concerts",
    "name": "Conciertos",
    "emoji": "🎶",
    "order": 48
  },
  {
    "id": "hiphop",
    "name": "Hip-hop",
    "emoji": "🎤",
    "order": 49
  },
  {
    "id": "electronic_music",
    "name": "Música electrónica",
    "emoji": "🎛️",
    "order": 50
  },
  {
    "id": "baking",
    "name": "Repostería",
    "emoji": "🧁",
    "order": 51
  },
  {
    "id": "wine",
    "name": "Vino",
    "emoji": "🍷",
    "order": 52
  },
  {
    "id": "craft_beer",
    "name": "Cerveza artesanal",
    "emoji": "🍺",
    "order": 53
  },
  {
    "id": "beauty",
    "name": "Belleza",
    "emoji": "💄",
    "order": 54
  },
  {
    "id": "sneakers",
    "name": "Sneakers",
    "emoji": "👟",
    "order": 55
  },
  {
    "id": "tattoos",
    "name": "Tatuajes",
    "emoji": "🖋️",
    "order": 56
  },
  {
    "id": "plants",
    "name": "Plantas",
    "emoji": "🪴",
    "order": 57
  },
  {
    "id": "gardening",
    "name": "Jardinería",
    "emoji": "🌱",
    "order": 58
  },
  {
    "id": "languages",
    "name": "Idiomas",
    "emoji": "🌍",
    "order": 59
  },
  {
    "id": "volunteering",
    "name": "Voluntariado",
    "emoji": "🤝",
    "order": 60
  },
  {
    "id": "sustainability",
    "name": "Sostenibilidad",
    "emoji": "♻️",
    "order": 61
  },
  {
    "id": "cosplay",
    "name": "Cosplay",
    "emoji": "🦸",
    "order": 62
  },
  {
    "id": "true_crime",
    "name": "Crímenes reales",
    "emoji": "🕵️",
    "order": 63
  },
  {
    "id": "collecting",
    "name": "Coleccionismo",
    "emoji": "🃏",
    "order": 64
  },
  {
    "id": "crafts",
    "name": "Manualidades",
    "emoji": "✂️",
    "order": 65
  },
  {
    "id": "streaming",
    "name": "Streaming",
    "emoji": "📺",
    "order": 66
  },
  {
    "id": "ai",
    "name": "IA",
    "emoji": "🤖",
    "order": 67
  },
  {
    "id": "personal_finance",
    "name": "Finanzas personales",
    "emoji": "💰",
    "order": 68
  },
  {
    "id": "philosophy",
    "name": "Filosofía",
    "emoji": "💭",
    "order": 69
  },
  {
    "id": "chess",
    "name": "Ajedrez",
    "emoji": "♟️",
    "order": 70
  },
  {
    "id": "board_games",
    "name": "Juegos de mesa",
    "emoji": "🎲",
    "order": 71
  }
];

if (!admin.apps.length) {
  admin.initializeApp({ projectId: PROJECT_ID });
}

const db = admin.firestore();

async function main() {
  console.log(`Seeding ${INTERESTS.length} interests into Firestore (${PROJECT_ID})...`);
  const batch = db.batch();
  for (const item of INTERESTS) {
    const ref = db.collection("interests").doc(item.id);
    batch.set(ref, {
      name: item.name,
      emoji: item.emoji,
      order: item.order,
      slug: item.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  await batch.commit();
  console.log("Done. Existing docs merged by slug id.");
  const snap = await db.collection("interests").get();
  console.log(`Total docs in interests/: ${snap.size}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
