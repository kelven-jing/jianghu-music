import { createServer } from "node:http";
import { createReadStream } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";

import { parseLrc } from "./lyrics.mjs";

const musicDir = process.env.MUSIC_DIR;
const port = Number(process.env.PORT ?? 8787);
const audioExtensions = new Set([".mp3"]);

if (!musicDir) {
  console.error("请先设置 MUSIC_DIR，再启动服务。");
  process.exit(1);
}

async function findAudioFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });

  const nestedResults = await Promise.all(
    entries.map(async (entry) => {
      const fullPath = path.join(directory, entry.name);

      if (entry.isDirectory()) {
        return findAudioFiles(fullPath);
      }

      if (!entry.isFile()) {
        return [];
      }

      const extension = path.extname(entry.name).toLowerCase();
      if (!audioExtensions.has(extension)) {
        return [];
      }

      const fileInfo = await stat(fullPath);
      const baseName = path.basename(entry.name, extension);
      const lyricsEntry = entries.find((candidate) => {
  return (
    candidate.isFile() &&
    path.extname(candidate.name).toLowerCase() === ".lrc"
  );
});

const lyricsPath = lyricsEntry
  ? path.join(directory, lyricsEntry.name)
  : null;

const hasLyrics = lyricsPath !== null;
      return [
        {
          id: path.relative(musicDir, fullPath).split(path.sep).join("/"),
          title: baseName,
          sizeBytes: fileInfo.size,
          hasLyrics,
          fullPath,
          lyricsPath: hasLyrics ? lyricsPath : null,
        },
      ];
    }),
  );

  return nestedResults.flat().sort((left, right) =>
    left.title.localeCompare(right.title, "zh-CN"),
  );
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, (character) => {
    return {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    }[character];
  });
}

function formatBytes(sizeBytes) {
  return `${(sizeBytes / 1024 / 1024).toFixed(1)} MB`;
}

function publicSong(song) {
  const { fullPath, lyricsPath, ...safeSong } = song;
  return safeSong;
}

function sendJson(response, statusCode, data) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(data, null, 2));
}

function sendAudio(request, response, song) {
  const totalSize = song.sizeBytes;
  const range = request.headers.range;

  if (!range) {
    response.writeHead(200, {
      "Content-Type": "audio/mpeg",
      "Content-Length": totalSize,
      "Accept-Ranges": "bytes",
    });
    createReadStream(song.fullPath).pipe(response);
    return;
  }

  const match = /^bytes=(\d*)-(\d*)$/.exec(range);
  if (!match) {
    response.writeHead(416, { "Content-Range": `bytes */${totalSize}` });
    response.end();
    return;
  }

  const [, startText, endText] = match;
  let start;
  let end;

  if (startText === "" && endText !== "") {
    const suffixLength = Number(endText);
    start = Math.max(totalSize - suffixLength, 0);
    end = totalSize - 1;
  } else {
    start = Number(startText);
    end = endText === "" ? totalSize - 1 : Number(endText);
  }

  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(end) ||
    start < 0 ||
    end < start ||
    start >= totalSize ||
    end >= totalSize
  ) {
    response.writeHead(416, { "Content-Range": `bytes */${totalSize}` });
    response.end();
    return;
  }

  response.writeHead(206, {
    "Content-Type": "audio/mpeg",
    "Content-Length": end - start + 1,
    "Content-Range": `bytes ${start}-${end}/${totalSize}`,
    "Accept-Ranges": "bytes",
  });

  createReadStream(song.fullPath, { start, end }).pipe(response);
}

async function readLyrics(song) {
  if (!song.lyricsPath) {
    return [];
  }

  return parseLrc(await readFile(song.lyricsPath, "utf8"));
}

const server = createServer(async (request, response) => {
  try {
    const requestUrl = new URL(
      request.url ?? "/",
      `http://${request.headers.host ?? "localhost"}`,
    );

    const songs = await findAudioFiles(musicDir);

    if (requestUrl.pathname === "/api/health") {
      return sendJson(response, 200, {
        ok: true,
        songCount: songs.length,
      });
    }

    if (requestUrl.pathname === "/api/library") {
      return sendJson(response, 200, {
        songs: songs.map(publicSong),
      });
    }

    if (requestUrl.pathname === "/api/audio") {
      const songId = requestUrl.searchParams.get("id");
      const song = songs.find((candidate) => candidate.id === songId);

      if (!song) {
        return sendJson(response, 404, { error: "歌曲不存在" });
      }

      sendAudio(request, response, song);
      return;
    }

    if (requestUrl.pathname === "/api/lyrics") {
      const songId = requestUrl.searchParams.get("id");
      const song = songs.find((candidate) => candidate.id === songId);

      if (!song) {
        return sendJson(response, 404, { error: "歌曲不存在" });
      }

      return sendJson(response, 200, {
        songId: song.id,
        lines: await readLyrics(song),
      });
    }

    if (requestUrl.pathname === "/") {
      const items = songs
        .map((song) => {
          const source = `/api/audio?id=${encodeURIComponent(song.id)}`;
          const lyricsLabel = song.hasLyrics ? "有歌词" : "无歌词";

          return `<li>
            <button
              class="song"
              data-id="${escapeHtml(song.id)}"
              data-source="${escapeHtml(source)}"
              data-title="${escapeHtml(song.title)}"
            >
              ${escapeHtml(song.title)}
            </button>
            <small>${formatBytes(song.sizeBytes)} · ${lyricsLabel}</small>
          </li>`;
        })
        .join("");

      response.writeHead(200, {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      });
      response.end(`<!doctype html>
<html lang="zh-CN">
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>江湖音乐</title>
  <style>
    body { max-width: 680px; margin: 32px auto; padding: 0 16px; font-family: system-ui, sans-serif; }
    audio { width: 100%; margin: 16px 0; }
    li { margin: 10px 0; }
    button { font: inherit; cursor: pointer; }
    small { color: #666; margin-left: 8px; }
    #lyrics { max-height: 280px; overflow-y: auto; padding: 12px; background: #f5f5f7; border-radius: 12px; }
    #lyrics p { margin: 10px 0; color: #666; }
    #lyrics p.active { color: #111; font-weight: 700; font-size: 1.05em; }
  </style>
  <body>
    <h1>江湖音乐</h1>
    <p id="now-playing">选择一首歌开始播放。共 ${songs.length} 首。</p>
    <audio id="player" controls preload="metadata"></audio>
    <section>
      <h2>歌词</h2>
      <div id="lyrics">选择一首带歌词的歌曲。</div>
    </section>
    <h2>音乐库</h2>
    <ol>${items}</ol>
    <script>
      const player = document.querySelector("#player");
      const status = document.querySelector("#now-playing");
      const lyricsElement = document.querySelector("#lyrics");
      let lyricLines = [];
      let activeIndex = -1;

      function renderLyrics(lines) {
        lyricLines = lines;
        activeIndex = -1;
        lyricsElement.replaceChildren();

        if (lines.length === 0) {
          lyricsElement.textContent = "这首歌没有匹配的 LRC 歌词。";
          return;
        }

        lines.forEach((line) => {
          const element = document.createElement("p");
          element.textContent = line.text;
          lyricsElement.append(element);
        });
      }

      function updateActiveLyrics() {
        const positionMs = player.currentTime * 1000;
        let nextIndex = -1;

        for (let index = 0; index < lyricLines.length; index += 1) {
          if (lyricLines[index].timeMs > positionMs) {
            break;
          }

          nextIndex = index;
        }

        if (nextIndex === activeIndex) {
          return;
        }

        const elements = lyricsElement.querySelectorAll("p");
        elements[activeIndex]?.classList.remove("active");
        elements[nextIndex]?.classList.add("active");
        elements[nextIndex]?.scrollIntoView({ block: "center", behavior: "smooth" });
        activeIndex = nextIndex;
      }

      document.querySelectorAll(".song").forEach((button) => {
        button.addEventListener("click", async () => {
          player.src = button.dataset.source;
          status.textContent = "正在播放：" + button.dataset.title;
          await player.play();

          const response = await fetch(
            "/api/lyrics?id=" + encodeURIComponent(button.dataset.id),
          );
          const data = await response.json();
          renderLyrics(data.lines);
        });
      });

      player.addEventListener("timeupdate", updateActiveLyrics);
      player.addEventListener("seeked", updateActiveLyrics);
    </script>
  </body>
</html>`);
      return;
    }

    sendJson(response, 404, { error: "Not found" });
  } catch (error) {
    console.error(error);
    sendJson(response, 500, { error: "无法读取音乐目录" });
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`江湖音乐服务已启动：http://127.0.0.1:${port}`);
});