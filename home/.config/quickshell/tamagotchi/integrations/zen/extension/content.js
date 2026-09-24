// En páginas de vídeo: cada medio segundo le cuenta a Mochi dónde está el vídeo (dentro de la
// ventana), si va o está en pausa, si es un anuncio (YouTube) y los momentos más vistos
// (el "heatmap" de YouTube, encima de la barra de progreso).
(() => {
    let peaksFor = "", peaks = [];

    // Momentos más vistos: del camino SVG del heatmap (x 0-1000 por capítulo, y 0-100: más
    // abajo = más visto). Picos = máximos locales altos, en segundos.
    function heatPeaks(duration) {
        const chapters = [...document.querySelectorAll(".ytp-heat-map-chapter")];
        if (!chapters.length || !duration)
            return [];
        const total = chapters.reduce((a, c) => a + c.getBoundingClientRect().width, 0) || 1;
        let off = 0;
        const pts = [];
        for (const c of chapters) {
            const w = c.getBoundingClientRect().width / total;
            const d = c.querySelector("path.ytp-heat-map-path, path")?.getAttribute("d") ?? "";
            const nums = d.match(/-?\d+(\.\d+)?/g)?.map(Number) ?? [];
            for (let i = 0; i + 1 < nums.length; i += 2)
                pts.push([off + (nums[i] / 1000) * w, 1 - nums[i + 1] / 100]);
            off += w;
        }
        pts.sort((a, b) => a[0] - b[0]);
        const out = [];
        for (let i = 1; i + 1 < pts.length; i++) {
            const [x, v] = pts[i];
            if (v > 0.72 && v >= pts[i - 1][1] && v >= pts[i + 1][1] && x > 0.02) {
                const t = x * duration;
                if (!out.length || t - out[out.length - 1] > 20)
                    out.push(Math.round(t));
            }
        }
        return out.slice(0, 12);
    }

    function tick() {
        const vids = [...document.querySelectorAll("video")].filter(v => v.getBoundingClientRect().width > 150);
        const v = vids.sort((a, b) => b.getBoundingClientRect().width - a.getBoundingClientRect().width)[0];
        if (!v)
            return;
        const r = v.getBoundingClientRect();
        const player = document.querySelector("#movie_player, .html5-video-player");
        const id = location.href;
        if (location.hostname.endsWith("youtube.com") && (peaksFor !== id || !peaks.length)) {
            peaks = heatPeaks(v.duration);
            if (peaks.length || peaksFor !== id)
                peaksFor = id;
        }
        browser.runtime.sendMessage({
            type: "video",
            site: location.hostname,
            url: location.href,
            title: document.title,
            playing: !v.paused && !v.ended && v.readyState > 2,
            time: v.currentTime,
            duration: isFinite(v.duration) ? v.duration : 0,
            ad: !!player?.classList.contains("ad-showing"),
            fullscreen: !!document.fullscreenElement,
            visible: document.visibilityState === "visible",
            // posición: del vídeo dentro del contenido, y del contenido dentro de la ventana
            rect: [r.x, r.y, r.width, r.height],
            inner: [window.mozInnerScreenX - window.screenX, window.mozInnerScreenY - window.screenY],
            outer: [window.outerWidth, window.outerHeight],
            peaks: location.hostname.endsWith("youtube.com") ? peaks : []
        }).catch(() => {});
    }

    setInterval(tick, 500);
    document.addEventListener("visibilitychange", tick);
})();
