'use strict';

hterm.defaultStorage = new lib.Storage.Memory();

window.fontSizeDetectionMethod = 'canvas';

function _postMessage(op, data) {
  window.webkit.messageHandlers.interOp.postMessage({op, data});
}

hterm.notify = function(params) {
  var def = (curr, fallback) => curr !== undefined ? curr : fallback;
  if (params === undefined || params === null) {
    params = {};
  }


  var title = def(params.title, window.document.title);
  if (!title)
    title = 'hterm';

  _postMessage('notify', {title, body: params.body})
}

hterm.Terminal.prototype.ringBell = function() {
  // Blink cursor on BEL character
  this.cursorNode_.style.backgroundColor = this.scrollPort_.getForegroundColor();
    
  setTimeout(() => this.restyleCursor_(), 200);
  
  _postMessage('ring-bell', null);
};

hterm.Terminal.prototype.copyStringToClipboard = function(content) {
  if (this.prefs_.get('enable-clipboard-notice')) {
    setTimeout(this.showOverlay.bind(this, hterm.notifyCopyMessage, 500), 200);
  }

  document.getSelection().removeAllRanges();
  _postMessage('copy', {content});
};

document.addEventListener('selectionchange', function() {
  _postMessage('selectionchange', term_getCurrentSelection());
});

hterm.Terminal.IO.prototype.sendString = function(string) {
  _postMessage('sendString', {string});
};

hterm.msg = function() {}; // TODO: show messages

function _colorComponents(colorStr) {
  if (!colorStr) {
    return [0, 0, 0]; // Default is black
  }

  return colorStr
    .replace(/[^0-9,]/g, '')
    .split(',')
    .map(s => parseInt(s));
}

// Before we fully load hterm. We set options here.
var _prefs = new hterm.PreferenceManager('blink');
var t = {prefs_: _prefs}; // <- `t` will become actual hterm instance after decorate.

function term_set(key, value) {
  _prefs.set(key, value);
}

function term_get(key) {
  return _prefs.get(key);
}

function term_setupDefaults() {
  term_set('copy-on-select', false);
  term_set('audible-bell-sound', '');
  term_set('receive-encoding', 'raw'); // we are UTF8
  term_set('allow-images-inline', true); // need to make it work
  term_set('scroll-wheel-may-send-arrow-keys', true)
}

function term_processKB(str) {
  if (!t.prompt) {
    return;
  }
  if (str) {
    t.prompt.processInput(str);
  }
}

function term_displayInput(str, display) {
  if (!t || !t.accessibilityReader_) {
    return;
  }
  
  t.accessibilityReader_.hasUserGesture = true;
  
  if (!display) {
    return;
  }
  
  if (str && !t.prompt._secure) {
    window.KeystrokeVisualizer.processInput(str);
  }
}


function term_setup(accessibilityEnabled) {
  t = new hterm.Terminal('blink');

  t.onTerminalReady = function() {
    window.installKB(t, t.scrollPort_.screen_);
    term_setAutoCarriageReturn(true);
    term_setClipboardWrite(false);

    t.setCursorVisible(true);
    t.io.onTerminalResize = function(cols, rows) {
      _postMessage('sigwinch', {cols, rows});
      if (t.prompt) {
        t.prompt.resize();
      }
    };

    var size = {
      cols: t.screenSize.width,
      rows: t.screenSize.height,
    };
    
    document.body.style.backgroundColor =
      t.scrollPort_.screen_.style.backgroundColor;
    var bgColor = _colorComponents(t.scrollPort_.screen_.style.backgroundColor);
    
    t.keyboard.characterEncoding = 'raw'; // we are UTF8. Fix for #507
    t.uninstallKeyboard();
    
    _postMessage('terminalReady', {size, bgColor});

    if (window.KeystrokeVisualizer) {
      window.KeystrokeVisualizer.enable();
    }
    t.setAccessibilityEnabled(accessibilityEnabled);
  };

  t.decorate(document.getElementById('terminal'));
}

function term_init(accessibilityEnabled, lockdownMode) {
  term_setupDefaults();
  try {
    applyUserSettings();
    //    var bgColor = term_get('background-color');
    //    document.body.style.backgroundColor = bgColor;
    //    document.body.parentNode.style.backgroundColor = bgColor;
    if (lockdownMode) {
      term_setup(accessibilityEnabled);
    } else {
      waitForFontFamily(term_setup);
    }
  } catch (e) {
    _postMessage('alert', {
      title: 'Error',
      message:
        'Failed to setup theme. Please check syntax of your theme.\n' +
        e.toString(),
    });
    term_setup(accessibilityEnabled);
  }
}

var _requestId = 0;
var _requestsMap = {};

class ApiRequest {
  constructor(name, request) {
    this.id = _requestId++;
    request.id = this.id;
    var self = this;
    this.promise = new Promise(function(resolve, reject) {
        self.resolve = resolve;
        self.reject = reject;
    });
    _requestsMap[this.id] = self
    _postMessage("api", {name, request: JSON.stringify(request)} );
    
    this.then = this.promise.then.bind(this.promise);
    this.catch = this.promise.catch.bind(this.promise);
  }
  
  cancel() {
    this.resolve(null);
    delete _requestsMap[this.id];
  }
}

function term_apiRequest(name, request) {
  return new ApiRequest(name, request)
}

function term_apiResponse(name, response) {
  var res = JSON.parse(response);
  var req = _requestsMap[res.requestId];
  if (!req) {
    return;
  }
  delete _requestsMap[req.id];
  req.resolve(res)
}


window.term_apiRequest = term_apiRequest;
window.term_apiResponse = term_apiResponse;

function term_write(data) {
  t.interpret(data);
}

function term_paste(str) {
  t.onPaste_({text: str || ''});
}

var _utf8TextDecoder = new TextDecoder('utf8');
function term_write_b64(b64str) {
  var bytes = base64js.toByteArray(b64str); // b64_to_uint8_array(b64str);
  var data = _utf8TextDecoder.decode(bytes);
  t.interpret(data);
};

function b64_to_uint8_array(b64Str) {
  var s = atob(b64Str);
  var len = s.length;
  var res = new Uint8Array(len);
  for (var i = 0; i < len; i++) {
    res[i] = s.charCodeAt(i);
  }
  return res;
}

function term_clear() {
  t.clear();
}

function term_reset() {
  t.reset();
}

function term_focus() {
  t.onFocusChange__(true);
}

function term_blur() {
  t.onFocusChange__(false);
}

function _setTermCoordinates(event, x, y) {
  // One based row/column stored on the mouse event.
  var ty = (y / t.scrollPort_.characterSize.height | 0) + 1;
  var tx = (x / t.scrollPort_.characterSize.width | 0) + 1;
//  console.log(`x:${x},y: ${y}, col:${tx}, row:${ty}`);
  event.terminalRow = ty;
  event.terminalColumn = tx;
}

function term_reportMouseClick(x, y, buttons, display) {
  if (!t.prompt) {
    return;
  }

  var event = new MouseEvent(name, {buttons});
  _setTermCoordinates(event, x, y);
  if (!t.prompt.processMouseClick(event)) {
    term_reportMouseEvent('mousedown', x, y, 1);
    term_reportMouseEvent('mouseup', x, y, 1);
  }
                                  
  if (display) {
     term_displayInput("👆", display);
  }
}

function term_reportMouseEvent(name, x, y, buttons) {
  if (!t.prompt) {
    return;
  }

  var event = new MouseEvent(name, {buttons});
  _setTermCoordinates(event, x, y);
  t.onMouse(event);
}

function term_reportWheelEvent(name, x, y, deltaX, deltaY) {
  if (!t.prompt) {
    return;
  }

  var event = new WheelEvent(name, {clientX: x, clientY: y, deltaX, deltaY});
  t.onMouse_Blink(event);
}

function term_setWidth(cols) {
  t.setWidth(cols);
}

function term_increaseFontSize() {
  var size = t.getFontSize();
  term_setFontSize(size + 1 + 'px');
}

function term_decreaseFontSize() {
  var size = t.getFontSize();
  term_setFontSize(size - 1 + 'px');
}

function term_resetFontSize() {
  term_setFontSize();
}

function term_scale(scale) {
  var minScale = 0.3;
  var maxScale = 3.0;
  scale = Math.max(minScale, Math.min(maxScale, scale));
  var fontSize = t.getFontSize();
  var newFontSize = Math.round(fontSize * scale);
  if (fontSize == newFontSize) {
    return;
  }
  term_setFontSize(newFontSize);
}

function term_setFontSize(size) {
  term_set('font-size', size);
  _postMessage('fontSizeChanged', {size: parseInt(size)});
}

function term_setFontFamily(name, fontSizeDetectionMethod) {
  window.fontSizeDetectionMethod = fontSizeDetectionMethod;
  term_set('font-family', name + ', "Blink Symbols", "DejaVu Sans Mono"');
}

function term_setClipboardWrite(state) {
  if (state === false) {
    t.vt.enableClipboardWrite = false;
  } else {
    t.vt.enableClipboardWrite = true;
  }
}

function term_appendUserCss(css) {
  var style = document.createElement('style');

  style.type = 'text/css';
  style.appendChild(document.createTextNode(css));

  document.head.appendChild(style);
}

function term_loadFontFromCss(url, name) {
  WebFont.load({
    custom: {
      families: [name],
      urls: [url],
    },
    active: function() {
      t.syncFontFamily();
    },
  });
  term_setFontFamily(name);
}

// <pure:links>
// Finds links in screen rows. `rows` is top to bottom, each {text, wrapped}; `width` is the
// terminal's column count; `strWidth` measures a string in cells. A row continues onto the next
// when the terminal wrapped it, or when it fills the full width with no gap at the join (how a
// wrapped line looks inside tmux, which repaints each row itself).
// Returns [{url, segments: [{row, start, end}]}] in screen order (indices into each row's text).
function blink_findUrls(rows, width, strWidth) {
  strWidth = strWidth || function (s) { return s.length; };
  var re = /(?:https?:\/\/|mailto:|ssh:\/\/)[^\s<>"'`─-▟]+/g;
  var out = [];
  var i = 0;
  while (i < rows.length) {
    var parts = [];
    var offset = 0;
    var j = i;
    for (;;) {
      var text = rows[j].text || '';
      parts.push({row: j, offset: offset, text: text});
      offset += text.length;
      var next = j + 1 < rows.length ? (rows[j + 1].text || '') : null;
      var joins = next !== null && text.length > 0 && (
        rows[j].wrapped ||
        (width > 0 && strWidth(text) >= width && !/\s$/.test(text) && next.length > 0 && !/^\s/.test(next)));
      if (!joins) { break; }
      j++;
    }
    var line = parts.map(function (p) { return p.text; }).join('');
    var m;
    re.lastIndex = 0;
    while ((m = re.exec(line)) !== null) {
      var url = m[0];
      // Sentence punctuation and an unmatched closing bracket are not part of the link.
      for (;;) {
        var last = url[url.length - 1];
        if (/[.,;:!?'"]/.test(last)) { url = url.slice(0, -1); continue; }
        if (last === ')' && url.split('(').length <= url.split(')').length - 1) { url = url.slice(0, -1); continue; }
        if (last === ']' && url.split('[').length <= url.split(']').length - 1) { url = url.slice(0, -1); continue; }
        break;
      }
      if (url.length < 8) { continue; }
      var start = m.index, end = m.index + url.length;
      var segments = [];
      parts.forEach(function (p) {
        var s = Math.max(start, p.offset), e = Math.min(end, p.offset + p.text.length);
        if (s < e) { segments.push({row: p.row, start: s - p.offset, end: e - p.offset}); }
      });
      out.push({url: url, segments: segments});
    }
    i = j + 1;
  }
  return out;
}
// </pure:links>

function _blinkScreenLinks() {
  var top = t.scrollPort_.getTopRowIndex();
  var count = t.scrollPort_.visibleRowCount;
  var total = t.getRowCount();
  var rows = [];
  for (var i = 0; i < count && top + i < total; i++) {
    // Rows are the terminal's own objects, not page elements: their text comes from
    // getRowsText, which also leaves out the line break after a row that wrapped.
    var text = t.getRowsText(top + i, top + i + 1);
    var wrapped = false;
    if (top + i + 1 < total) {
      var next = t.getRowsText(top + i + 1, top + i + 2);
      wrapped = t.getRowsText(top + i, top + i + 2).length === text.length + next.length;
    }
    rows.push({text: text, wrapped: wrapped});
  }
  return {rows: rows, links: blink_findUrls(rows, t.screenSize.width, lib.wc.strWidth)};
}

// Links on screen, top to bottom, without repeats. Includes OSC 8 hyperlinks.
function term_visibleUrls() {
  try {
    var found = _blinkScreenLinks().links.map(function (l) { return {url: l.url, row: l.segments[0].row}; });
    var h = t.scrollPort_.characterSize.height || 1;
    document.querySelectorAll('.uri-node').forEach(function (n) {
      var uri = n.getAttribute('title') || n.uri;
      if (uri) { found.push({url: uri, row: n.getBoundingClientRect().top / h | 0}); }
    });
    found.sort(function (a, b) { return a.row - b.row; });
    var seen = {}, urls = [];
    found.forEach(function (f) { if (!seen[f.url]) { seen[f.url] = true; urls.push(f.url); } });
    return urls;
  } catch (e) {
    console.log('term_visibleUrls failed: ' + e);
    return [];
  }
}

// The link under a point in the view, or null.
function term_urlAtPoint(x, y) {
  try {
    var el = document.elementFromPoint(x, y);
    var node = el && el.closest ? el.closest('.uri-node') : null;
    if (node) { return node.getAttribute('title') || node.uri || null; }
    var size = t.scrollPort_.characterSize;
    var row = y / size.height | 0, col = x / size.width | 0;
    var screen = _blinkScreenLinks();
    for (var i = 0; i < screen.links.length; i++) {
      var segments = screen.links[i].segments;
      for (var k = 0; k < segments.length; k++) {
        var s = segments[k];
        if (s.row !== row) { continue; }
        var text = screen.rows[row].text;
        var from = lib.wc.strWidth(text.slice(0, s.start)), to = lib.wc.strWidth(text.slice(0, s.end));
        if (col >= from && col < to) { return screen.links[i].url; }
      }
    }
  } catch (e) {}
  return null;
}

// Only the rows on screen exist in the page, so a native selection can never cover the
// scrollback. Select All marks what is visible and remembers that selection; while it stays
// unchanged, copy gets the whole buffer instead.
var _blinkSelectAll = null;

function term_selectAll() {
  var selection = document.getSelection();
  selection.selectAllChildren(t.scrollPort_.screen_);
  _blinkSelectAll = {visible: selection.toString()};
}

function _blinkBufferText() {
  return t.getRowsText(0, t.getRowCount()).replace(/\s+$/, '');
}

function term_getCurrentSelection() {
  const selection = document.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.type === 'Caret') {
    _blinkSelectAll = null;
    return {base: '', offset: 0, text: ''};
  }

  const r = selection.getRangeAt(0).getBoundingClientRect();

  const rect = `{{${r.x}, ${r.y}},{${r.width},${r.height}}}`;

  return {
    base: selection.baseNode.textContent,
    offset: selection.baseOffset,
    text: _blinkSelectionText(selection),
    rect,
  };
}

function _blinkSelectionText(selection) {
  const text = selection.toString() || "";
  if (_blinkSelectAll) {
    if (_blinkSelectAll.visible === text) {
      return _blinkBufferText();
    }
    _blinkSelectAll = null;
  }
  return text;
}

function _modifySelectionByLine(direction) {
  var selection = document.getSelection();
  var fNode = selection.focusNode;
  var fOffset = selection.focusOffset;
  var aNode = selection.anchorNode;
  var aOffset = selection.anchorOffset;

  var dy =
    direction === 'left'
      ? -t.scrollPort_.characterSize.height
      : t.scrollPort_.characterSize.height;
  var dx = t.scrollPort_.characterSize.width;
  var range = selection.getRangeAt(0);

  var topLeft = true;
  if (fNode === aNode) {
    topLeft = fOffset < aOffset;
  } else {
    topLeft = range.compareNode(selection.focusNode) !== Range.NODE_AFTER;
  }

  if (topLeft) {
    // top left
    var rect = _filteredRects(range)[0];
    var point = {x: rect.left, y: rect.top + Math.abs(dy) * 0.5};
    var newRange = document.caretRangeFromPoint(point.x, point.y + dy);
    if (!newRange) {
      selection.modify('extend', direction, 'line');
    } else {
      if (newRange.startContainer.textContent.length <= newRange.startOffset) {
        if (
          newRange.startContainer.nodeName === 'X-ROW' &&
          newRange.startOffset === 0
        ) {
          selection.setBaseAndExtent(
            aNode,
            aOffset,
            newRange.startContainer,
            newRange.startOffset,
          );
          selection.modify('extend', 'left', 'character');
        } else {
          selection.setBaseAndExtent(
            aNode,
            aOffset,
            newRange.startContainer,
            Math.max(newRange.startOffset - 1, 0),
          );
        }
      } else {
        selection.setBaseAndExtent(
          aNode,
          aOffset,
          newRange.startContainer,
          newRange.startOffset,
        );
      }
    }
  } else {
    // bottom right
    var rects = _filteredRects(range);
    var rect = rects[rects.length - 1];
    var point = {x: rect.right, y: rect.bottom - Math.abs(dy) * 0.5};
    var newRange = document.caretRangeFromPoint(point.x, point.y + dy);
    if (newRange == null) {
      point.x -= dx * 0.5;
    }
    newRange = document.caretRangeFromPoint(point.x, point.y + dy);
    selection.setBaseAndExtent(
      aNode,
      aOffset,
      newRange.startContainer,
      newRange.startOffset,
    );
  }
}

function _filteredRects(range) {
  var res = [];
  var rects = range.getClientRects();
  for (var i = 0; i < rects.length; i++) {
    var r = rects[i];
    if (r.width > 0) {
      res.push(r);
    }
  }
  return res;
}

function term_modifySelection(direction, granularity) {
  var selection = document.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return;
  }

  var fNode = selection.focusNode;
  var fOffset = selection.focusOffset;
  var aNode = selection.anchorNode;
  var aOffset = selection.anchorOffset;

  if (granularity === 'line') {
    _modifySelectionByLine(direction);
    if (selection.isCollapsed) {
      selection.setBaseAndExtent(fNode, fOffset, aNode, aOffset);
      _modifySelectionByLine(direction);
    }

    return;
  }

  selection.modify('extend', direction, granularity);

  // we collapse selection, so swap direction and rerun modification again
  if (selection.isCollapsed) {
    selection.setBaseAndExtent(fNode, fOffset, aNode, aOffset);
    selection.modify('extend', direction, granularity);
  }
}

function term_modifySideSelection() {
  var selection = document.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return;
  }

  selection.setBaseAndExtent(
    selection.focusNode,
    selection.focusOffset,
    selection.anchorNode,
    selection.anchorOffset,
  );
}

function term_cleanSelection() {
  _blinkSelectAll = null;
  document.getSelection().removeAllRanges();
}

function waitForFontFamily(callback) {
  const fontFamily = term_get('font-family');
  if (!fontFamily) {
    return callback();
  }

  const families = fontFamily.split(/\s*,\s*/);

  WebFont.load({
    custom: {families},
    active: callback,
    inactive: callback,
  });
}

function term_applySexyTheme(theme) {
  term_set('color-palette-overrides', theme.color);
  term_set('foreground-color', theme.foreground);
  term_set('background-color', theme.background);
}

// Setting a colour back to hterm's own default value does not always repaint an open
// terminal, so after a theme is applied the colours are pushed to the screen directly.
function term_syncColors() {
  setTimeout(function () {
    if (!t || !t.setBackgroundColor || !t.scrollPort_) {
      return;
    }
    t.setForegroundColor(term_get('foreground-color'));
    t.setBackgroundColor(term_get('background-color'));
    t.setCursorColor(term_get('cursor-color'));
    t.scrollPort_.invalidate();
  }, 30);
}

function term_setAutoCarriageReturn(state) {
  t.setAutoCarriageReturn(state);
}

function term_restore() {
  t.primaryScreen_.textAttributes.reset();
  t.setVTScrollRegion(null, null);
  t.setCursorVisible(true);
}
