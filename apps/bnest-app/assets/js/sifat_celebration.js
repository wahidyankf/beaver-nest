const celebrationShapes = ["star", "dot", "diamond", "spark"];

const reducedMotionPreferred = () =>
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** @template T @param {T[]} items @returns {T} */
const randomItem = (items) => {
  const item = items[Math.floor(Math.random() * items.length)];

  if (item === undefined) {
    throw new Error("Cannot select from an empty list");
  }

  return item;
};

const createConfetti = () => {
  const piece = document.createElement("i");
  const horizontalDistance = Math.round((Math.random() - 0.5) * 260);
  const verticalDistance = -(90 + Math.round(Math.random() * 230));
  const rotation = Math.round((Math.random() - 0.5) * 520);

  piece.className = `sifat-confetti is-${randomItem(celebrationShapes)}`;
  piece.style.setProperty("--celebration-x", `${horizontalDistance}px`);
  piece.style.setProperty("--celebration-y", `${verticalDistance}px`);
  piece.style.setProperty("--celebration-rotation", `${rotation}deg`);
  piece.addEventListener("animationend", () => piece.remove(), { once: true });

  return piece;
};

export const celebrateSifatAnswer = () => {
  if (reducedMotionPreferred()) return;

  const container = document.querySelector("#sifat-celebrations");
  if (!container) return;

  const pieces = Array.from({ length: 14 }, createConfetti);
  container.replaceChildren(...pieces);

  requestAnimationFrame(() => {
    pieces.forEach((piece) => piece.classList.add("is-flying"));
  });
};
