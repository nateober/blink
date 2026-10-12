// Run: node tools/termjs-tests/links.test.js
// Tests the pure link finder in Resources/term.js (the block between the pure:links markers).
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const src = fs.readFileSync(path.join(__dirname, '../../Resources/term.js'), 'utf8');
const block = src.split('// <pure:links>')[1].split('// </pure:links>')[0];
const blink_findUrls = new Function(block + '\nreturn blink_findUrls;')();

const rows = (...texts) => texts.map(t => (typeof t === 'string' ? {text: t, wrapped: false} : t));
const urls = (r, width = 80) => blink_findUrls(r, width).map(l => l.url);

// plain link, with sentence punctuation after it
assert.deepStrictEqual(urls(rows('see https://example.com/a?b=1.')), ['https://example.com/a?b=1']);
// several on a row, and brackets
assert.deepStrictEqual(urls(rows('(https://a.io/x) and [https://b.io/y]')), ['https://a.io/x', 'https://b.io/y']);
// balanced parentheses stay
assert.deepStrictEqual(urls(rows('https://en.wikipedia.org/wiki/Foo_(bar)')), ['https://en.wikipedia.org/wiki/Foo_(bar)']);
// terminal-wrapped link joins across rows
let found = blink_findUrls(rows({text: 'go https://example.com/abc', wrapped: true}, 'def/ghi done'), 26);
assert.strictEqual(found[0].url, 'https://example.com/abcdef/ghi');
assert.deepStrictEqual(found[0].segments, [{row: 0, start: 3, end: 26}, {row: 1, start: 0, end: 7}]);
// tmux-style wrap: the row is full width, no wrap flag
assert.deepStrictEqual(urls(rows('go https://example.com/abc', 'def/ghi done'), 26), ['https://example.com/abcdef/ghi']);
// a short row does not join the next one
assert.deepStrictEqual(urls(rows('go https://example.com/abc', 'def/ghi done'), 80), ['https://example.com/abc']);
// a full-width row followed by an indented row does not join
assert.deepStrictEqual(urls(rows('go https://example.com/abc', '  next'), 26), ['https://example.com/abc']);
// box-drawing borders end a link
assert.deepStrictEqual(urls(rows('│ https://example.com/x│')), ['https://example.com/x']);
// other schemes; bare scheme is ignored
assert.deepStrictEqual(urls(rows('mailto:a@b.co ssh://host http://')), ['mailto:a@b.co', 'ssh://host']);
// nothing
assert.deepStrictEqual(urls(rows('no links here', '')), []);

console.log('links: 10 checks passed');
