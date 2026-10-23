const timestampPattern = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

function fractionalMilliseconds(fraction = "") {
  return Number(fraction.padEnd(3, "0").slice(0, 3));
}

export function parseLrc(source) {
  const lines = [];

  for (const rawLine of source.replace(/\r\n?/g, "\n").split("\n")) {
    const text = rawLine.replace(timestampPattern, "").trim();

    if (!text) {
      continue;
    }

    timestampPattern.lastIndex = 0;
    let match;

    while ((match = timestampPattern.exec(rawLine)) !== null) {
      const minutes = Number(match[1]);
      const seconds = Number(match[2]);
      const milliseconds = fractionalMilliseconds(match[3]);

      if (seconds >= 60) {
        continue;
      }

      lines.push({
        timeMs: minutes * 60_000 + seconds * 1_000 + milliseconds,
        text,
      });
    }
  }

  return lines.sort((left, right) => left.timeMs - right.timeMs);
}

export function activeLineIndex(lines, positionMs) {
  let activeIndex = -1;

  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index].timeMs > positionMs) {
      break;
    }

    activeIndex = index;
  }

  return activeIndex;
}