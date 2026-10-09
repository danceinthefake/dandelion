// The search API marks matching words with `[[` and `]]` in a plain-text snippet. The snippet is
// whatever an admin typed, so it must never reach the page as HTML: this turns it into a list of
// text pieces, each marked or not, and the template renders them as text (`{{ }}`, never `v-html`).
export type Piece = { text: string; mark: boolean };

export function pieces(snippet: string | null | undefined): Piece[] {
  if (!snippet) return [];
  const out: Piece[] = [];
  const re = /\[\[(.*?)\]\]/gs;
  let last = 0;
  for (const m of snippet.matchAll(re)) {
    if (m.index > last) out.push({ text: snippet.slice(last, m.index), mark: false });
    out.push({ text: m[1], mark: true });
    last = m.index + m[0].length;
  }
  if (last < snippet.length) out.push({ text: snippet.slice(last), mark: false });
  return out;
}
