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

console.log('resizehold: 6 checks passed');
