.pragma library

// Rasgos de carácter de Mochi. Los eliges al crearlo (3) y ganas un hueco más al subir de
// nivel (10, 20 y 35). Cada uno cambia de verdad cómo se comporta (shell.qml: has("id")).
// `vs`: rasgos que no pueden ir juntos.

const list = [
    {
        id: "dormilon",
        name: "Dormilón",
        icon: "bedtime",
        desc: "Se le cierran los ojos antes y le encanta su nido.",
        vs: ["inquieto"]
    },
    {
        id: "inquieto",
        name: "Inquieto",
        icon: "bolt",
        desc: "No para quieto: pasea y salta mucho más.",
        vs: ["dormilon"]
    },
    {
        id: "curioso",
        name: "Curioso",
        icon: "search",
        desc: "Todo le llama la atención: ventanas nuevas, avisos, vídeos.",
        vs: []
    },
    {
        id: "mimoso",
        name: "Mimoso",
        icon: "favorite",
        desc: "Te busca y te coge cariño más rápido.",
        vs: ["timido"]
    },
    {
        id: "timido",
        name: "Tímido",
        icon: "visibility_off",
        desc: "Se asusta con facilidad y prefiere quedarse lejos del ratón.",
        vs: ["mimoso", "valiente"]
    },
    {
        id: "jugueton",
        name: "Juguetón",
        icon: "sports_esports",
        desc: "Te propone jugar al escondite a menudo.",
        vs: []
    },
    {
        id: "nadador",
        name: "Nadador",
        icon: "pool",
        desc: "Se pasa el día buceando por el marco.",
        vs: []
    },
    {
        id: "bailongo",
        name: "Bailongo",
        icon: "music_note",
        desc: "Con música baila siempre, y con más ganas.",
        vs: []
    },
    {
        id: "cafetero",
        name: "Cafetero",
        icon: "coffee",
        desc: "El café le sienta de maravilla y le dura más.",
        vs: []
    },
    {
        id: "friolero",
        name: "Friolero",
        icon: "ac_unit",
        desc: "Tirita en cuanto refresca un poco.",
        vs: ["caluroso"]
    },
    {
        id: "caluroso",
        name: "Caluroso",
        icon: "local_fire_department",
        desc: "Con el PC caliente se derrite antes.",
        vs: ["friolero"]
    },
    {
        id: "noctambulo",
        name: "Noctámbulo",
        icon: "dark_mode",
        desc: "Por la noche está más despierto que de día.",
        vs: ["madrugador"]
    },
    {
        id: "madrugador",
        name: "Madrugador",
        icon: "wb_sunny",
        desc: "Por la mañana va a tope; por la noche cae rendido.",
        vs: ["noctambulo"]
    },
    {
        id: "valiente",
        name: "Valiente",
        icon: "shield",
        desc: "Ni truenos, ni avisos urgentes, ni caídas: no se asusta.",
        vs: ["timido"]
    },
    {
        id: "presumido",
        name: "Presumido",
        icon: "auto_awesome",
        desc: "Cuando está muy contento, se pone arcoíris un momento.",
        vs: []
    }
];

function byId(id) {
    return list.find(t => t.id === id) || null;
}

// Huecos según el nivel: 3 al principio, +1 a los niveles 10, 20 y 35
function slots(level) {
    return 3 + (level >= 10 ? 1 : 0) + (level >= 20 ? 1 : 0) + (level >= 35 ? 1 : 0);
}

// Siguiente nivel que da un hueco más (0 si ya los tiene todos)
function nextSlotAt(level) {
    return level < 10 ? 10 : level < 20 ? 20 : level < 35 ? 35 : 0;
}

// ¿Choca con alguno de los elegidos?
function clashes(id, chosen) {
    const t = byId(id);
    return !!t && chosen.some(c => t.vs.includes(c));
}

// Limpia una lista: ids válidos, sin repetir, sin choques, como mucho `max`
function clean(ids, max) {
    const out = [];
    for (const id of ids || []) {
        if (out.length >= max)
            break;
        if (byId(id) && !out.includes(id) && !clashes(id, out))
            out.push(id);
    }
    return out;
}
