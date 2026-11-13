// Run: node tools/termjs-tests/syncoutput.test.js
// Synchronized output (DEC mode 2026) in Resources/hterm_all.patches.js: between
// CSI ? 2026 h and CSI ? 2026 l nothing is painted, and the frame is painted once at the end.
const fs = require('fs');
const path = require('path');
const assert = require('assert');

function load() {
  const calls = [];
  const timers = [];
  const hterm = {ScrollPort: function () {}, Terminal: function () {}, VT: function () {}};
  hterm.ScrollPort.prototype.onResize_ = function () {};
  hterm.ScrollPort.prototype.scheduleRedraw = function () { calls.push('redraw'); };
  hterm.Terminal.prototype.onResize_ = function () {};
  hterm.Terminal.prototype.getCursorRow = function () { return 0; };
  hterm.Terminal.prototype.scheduleSyncCursorPosition_ = function () { calls.push('cursor'); };
  hterm.VT.prototype.setDECMode = function (code, state) { calls.push(`mode ${code} ${state}`); };
  const fakeSetTimeout = (fn, ms) => { timers.push({fn, ms}); return timers.length; };
  const fakeClearTimeout = (id) => { if (id) timers[id - 1] = null; };
  const patches = fs.readFileSync(path.join(__dirname, '../../Resources/hterm_all.patches.js'), 'utf8');
  new Function('hterm', 'window', 'setTimeout', 'clearTimeout', patches)(hterm, {}, fakeSetTimeout, fakeClearTimeout);

  const renderer = {
    touch() { calls.push('touch'); },
    touchRow(row) { calls.push(`row ${row}`); },
  };
  const port = new hterm.ScrollPort();
  port.renderRef = renderer;
  const term = new hterm.Terminal();
  term.scrollPort_ = port;
  const vt = new hterm.VT();
  vt.terminal = term;
  return {calls, timers, port, term, vt, renderer};
}

// Outside a frame everything paints as before, and other modes pass through.
let t = load();
t.port.scheduleRedraw(); t.term.scheduleSyncCursorPosition_(); t.vt.setDECMode('25', true);
assert.deepStrictEqual(t.calls, ['redraw', 'cursor', 'mode 25 true']);
t.vt.setDECMode('1003', true);
assert.strictEqual(t.calls.pop(), 'mode 1002 true', 'the older 1003 patch still applies');

// Inside a frame nothing paints; closing it paints once, rows as one full touch.
t = load();
t.vt.setDECMode('2026', true);
t.port.scheduleRedraw(); t.port.scheduleRedraw();
t.renderer.touchRow(3); t.renderer.touchRow(4); t.renderer.touch();
t.term.scheduleSyncCursorPosition_();
assert.deepStrictEqual(t.calls, [], 'held while the frame is open, and 2026 is not passed to hterm');
t.vt.setDECMode('2026', false);
assert.deepStrictEqual(t.calls, ['redraw', 'touch', 'cursor']);
t.renderer.touchRow(5);
assert.strictEqual(t.calls.pop(), 'row 5', 'painting resumes after the frame');

// A frame that changed nothing paints nothing.
t = load();
t.vt.setDECMode(2026, true); t.vt.setDECMode(2026, false);
assert.deepStrictEqual(t.calls, []);

// An app that never closes its frame cannot freeze the screen: the watchdog closes it.
t = load();
t.vt.setDECMode('2026', true);
t.renderer.touchRow(1);
const watchdog = t.timers.filter(Boolean).pop();
assert.ok(watchdog && watchdog.ms <= 200, 'a short watchdog is armed');
watchdog.fn();
assert.deepStrictEqual(t.calls, ['touch']);
t.renderer.touchRow(2);
assert.strictEqual(t.calls.pop(), 'row 2');

// Closing a frame that was never opened does nothing.
t = load();
t.vt.setDECMode('2026', false);
assert.deepStrictEqual(t.calls, []);

console.log('syncoutput ok');
