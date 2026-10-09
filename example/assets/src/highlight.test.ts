// node --test src/*.test.ts   (Node strips the types itself: nothing to install)
import { test } from "node:test";
import assert from "node:assert/strict";
import { pieces } from "./highlight.ts";

test("marks the words between [[ and ]]", () => {
  assert.deepEqual(pieces("fresh [[green]] tea from the [[hills]]"), [
    { text: "fresh ", mark: false },
    { text: "green", mark: true },
    { text: " tea from the ", mark: false },
    { text: "hills", mark: true },
  ]);
});

test("no markers is one plain piece; nothing is nothing", () => {
  assert.deepEqual(pieces("just text"), [{ text: "just text", mark: false }]);
  assert.deepEqual(pieces(null), []);
  assert.deepEqual(pieces(""), []);
  assert.deepEqual(pieces(undefined), []);
});

test("html in the text stays text: it is returned as a string to be shown, not parsed", () => {
  const out = pieces("<img src=x onerror=alert(1)> [[great]] <b>tea</b>");
  assert.equal(out.map((p) => p.text).join(""), "<img src=x onerror=alert(1)> great <b>tea</b>");
  assert.deepEqual(out.filter((p) => p.mark).map((p) => p.text), ["great"]);
});

test("an unclosed or stray marker is left as it is", () => {
  assert.deepEqual(pieces("a [[b"), [{ text: "a [[b", mark: false }]);
  assert.deepEqual(pieces("a ]] b"), [{ text: "a ]] b", mark: false }]);
});

test("adjacent and empty marks", () => {
  assert.deepEqual(pieces("[[a]][[b]]"), [
    { text: "a", mark: true },
    { text: "b", mark: true },
  ]);
  assert.deepEqual(pieces("x[[]]y"), [
    { text: "x", mark: false },
    { text: "", mark: true },
    { text: "y", mark: false },
  ]);
});
