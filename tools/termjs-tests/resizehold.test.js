// Run: node tools/termjs-tests/resizehold.test.js
// Tests the resize hold in Resources/term.js (the block between the pure:resizehold markers),
// and that hterm_all.patches.js routes both resize entry points through it.
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const src = fs.readFileSync(path.join(__dirname, '../../Resources/term.js'), 'utf8');
const block = src.split('// <pure:resizehold>')[1].split('// </pure:resizehold>')[0];
const make = new Function(block + '\nreturn blink_makeResizeHold;')();

// not held: nothing is skipped, ending a hold that never started does nothing
let h = make();
assert.strictEqual(h.skips(), false);
assert.strictEqual(h.set(false), false);

// held with no size change: ending the hold runs nothing
h = make();
assert.strictEqual(h.set(true), false);
assert.strictEqual(h.set(false), false);

// held across a hide and a show: both skipped, exactly one resize at the end
h = make();
h.set(true);
assert.strictEqual(h.skips(), true);
assert.strictEqual(h.skips(), true);
assert.strictEqual(h.set(false), true);
assert.strictEqual(h.set(false), false);
assert.strictEqual(h.skips(), false);

// holding again while held keeps the remembered change
h = make();
h.set(true); h.skips();
assert.strictEqual(h.set(true), false);
assert.strictEqual(h.set(false), true);

// The patches: a fake hterm, the real patch file, the real hold.
const calls = [];
const hterm = {
  ScrollPort: function () {}, Terminal: function () {}, VT: function () {},
};
hterm.ScrollPort.prototype.onResize_ = function () { calls.push('port'); };
hterm.Terminal.prototype.onResize_ = function () { calls.push('term'); };
hterm.Terminal.prototype.getCursorRow = function () { return 7; };
hterm.VT.prototype.setDECMode = function () {};
const window = {_blinkResizeHold: make()};
const patches = fs.readFileSync(path.join(__dirname, '../../Resources/hterm_all.patches.js'), 'utf8');
new Function('hterm', 'window', patches)(hterm, window);
const port = new hterm.ScrollPort(), term = new hterm.Terminal();

port.onResize_(); term.onResize_();
assert.deepStrictEqual(calls, ['port', 'term']);
window._blinkResizeHold.set(true);
port.onResize_(); term.onResize_();
assert.deepStrictEqual(calls, ['port', 'term'], 'held: neither entry point reflows');
assert.strictEqual(window._blinkResizeHold.set(false), true);
port.onResize_();
assert.deepStrictEqual(calls, ['port', 'term', 'port']);

// The prompt follows the cursor through a reflow.
const rowBlock = src.split('// <pure:promptrow>')[1].split('// </pure:promptrow>')[0];
const promptRow = new Function(rowBlock + '\nreturn blink_promptStartRow;')();
assert.strictEqual(promptRow(20, 20, 32), 32);   // grid grew, 12 rows came back from scrollback
assert.strictEqual(promptRow(32, 32, 20), 20);   // grid shrank
assert.strictEqual(promptRow(18, 20, 32), 30);   // two-line prompt: start row keeps its distance
assert.strictEqual(promptRow(5, 5, 5), 5);       // width only
assert.strictEqual(promptRow(1, 3, 0), 0);       // never above the first row

// The patched terminal resize exposes the cursor row from before the reflow, then clears it.
let seen = null;
hterm.Terminal.prototype.onResize_original = function () { seen = this.blinkCursorRowBeforeResize_; };
term.onResize_();
assert.strictEqual(seen, 7);
assert.strictEqual(term.blinkCursorRowBeforeResize_, null);

console.log('resizehold: 8 checks passed');
