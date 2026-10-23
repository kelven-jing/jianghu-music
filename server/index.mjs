import { createServer } from "node:http";
import { readdir, stat } from "node:fs/promises";
import path from "node:path";

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

      return [
        {
          id: path.relative(musicDir, fullPath).split(path.sep).join("/"),
          title: path.basename(entry.name, extension),
          sizeBytes: fileInfo.size,
        },
      ];
    }),
  );

  return nestedResults.flat();
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

function sendJson(response, statusCode, data) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(data, null, 2));
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
      return sendJson(response, 200, { songs });
    }

    if (requestUrl.pathname === "/") {
      const items = songs
        .map(
          (song) =>
            `<li><strong>${escapeHtml(song.title)}</strong><br><small>${escapeHtml(song.id)}</small></li>`,
        )
        .join("");

      response.writeHead(200, {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      });
      response.end(`<!doctype html>
<html lang="zh-CN">
  <meta charset="utf-8">
  <title>江湖音乐</title>
  <body>
    <h1>江湖音乐</h1>
    <p>已发现 ${songs.length} 首 MP3。</p>
    <ol>${items}</ol>
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