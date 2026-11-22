// Calculator Pro — a working calculator. A secret key sequence (arrows/digits ending with Enter)
// hands over to the main program; a wrong sequence does nothing at all, so nothing looks hidden.
(function (root) {
    'use strict';

    // ---- Scientific calculator (pure; also used by the tests) ----
    // The expression is kept as display text: digits . + − × ÷ ^ ( ) π e, prefix functions
    // "sin(" "cos(" "tan(" "ln(" "log(" "√(" and postfix ² ! ⁻¹ %. Trig works in degrees.
    const FUNCS = {
        'sin': x => Math.sin(x * Math.PI / 180), 'cos': x => Math.cos(x * Math.PI / 180),
        'tan': x => (Math.abs(((x % 180) + 180) % 180 - 90) < 1e-12) ? NaN : Math.tan(x * Math.PI / 180),
        'ln': Math.log, 'log': Math.log10, '√': Math.sqrt,
    };
    const UNITS = ['sin(', 'cos(', 'tan(', 'ln(', 'log(', '√(', '⁻¹'];

    function fact(n) {
        if (n < 0 || n > 170 || Math.floor(n) !== n) return NaN;
        let r = 1; for (let i = 2; i <= n; i++) r *= i; return r;
    }

    function tokenize(str) {
        const out = []; let i = 0;
        while (i < str.length) {
            const c = str[i];
            if (/[0-9.]/.test(c)) {
                let j = i; while (j < str.length && /[0-9.]/.test(str[j])) j++;
                let t = str.slice(i, j);
                if ((t.match(/\./g) || []).length > 1 || t === '.') throw new Error('num');
                const ex = str.slice(j).match(/^e(−?[0-9]+)/); // a result shown as 1.2e−7
                if (ex) { t += 'e' + ex[1].replace('−', '-'); j += ex[0].length; }
                out.push({ t: 'n', v: parseFloat(t) }); i = j; continue;
            }
            const f = ['sin', 'cos', 'tan', 'log', 'ln', '√'].find(n => str.startsWith(n, i));
            if (f) { out.push({ t: 'f', v: f }); i += f.length; continue; }
            if (str.startsWith('⁻¹', i)) { out.push({ t: 'post', v: '⁻¹' }); i += 2; continue; }
            if (c === 'π') out.push({ t: 'n', v: Math.PI });
            else if (c === 'e') out.push({ t: 'n', v: Math.E });
            else if ('²!%'.includes(c)) out.push({ t: 'post', v: c });
            else if ('+−×÷^()'.includes(c)) out.push({ t: c });
            else throw new Error('char');
            i++;
        }
        return out;
    }

    // Recursive descent; unclosed "(" are closed at the end; "2π" / "2(3)" multiply.
    function evaluate(str) {
        const tk = tokenize(str); let p = 0;
        const peek = () => tk[p], eat = t => (tk[p] && tk[p].t === t) ? tk[p++] : null;
        const startsValue = x => x && (x.t === 'n' || x.t === 'f' || x.t === '(');
        function expr() { let v = term(); for (;;) { if (eat('+')) v += term(); else if (eat('−')) v -= term(); else return v; } }
        function term() {
            let v = unary();
            for (;;) {
                if (eat('×')) v *= unary(); else if (eat('÷')) { const d = unary(); v = d === 0 ? NaN : v / d; }
                else if (startsValue(peek())) v *= unary(); else return v;
            }
        }
        function unary() { if (eat('−')) return -unary(); if (eat('+')) return unary(); return power(); }
        function power() { const b = postfix(); return eat('^') ? Math.pow(b, unary()) : b; }
        function postfix() {
            let v = primary();
            for (let x = peek(); x && x.t === 'post'; x = peek()) {
                p++;
                v = x.v === '²' ? v * v : x.v === '!' ? fact(v) : x.v === '%' ? v / 100 : (v === 0 ? NaN : 1 / v);
            }
            return v;
        }
        function primary() {
            const x = tk[p++];
            if (!x) throw new Error('end');
            if (x.t === 'n') return x.v;
            if (x.t === 'f') { if (!eat('(')) throw new Error('paren'); const v = expr(); eat(')'); return FUNCS[x.v](v); }
            if (x.t === '(') { const v = expr(); eat(')'); return v; }
            throw new Error('syntax');
        }
        const v = expr();
        if (p < tk.length) throw new Error('trailing');
        return v;
    }

    function fmt(n) {
        if (typeof n !== 'number' || !isFinite(n)) return 'Error';
        if (Math.abs(n) < 1e-12) return '0';
        const r = parseFloat(n.toPrecision(12));
        return (Math.abs(r) >= 1e15 || Math.abs(r) < 1e-9) ? r.toExponential(6).replace('e+', 'e') : String(r);
    }

    function newCalc() { return { expr: '', prev: '', done: false }; }

    function press(s, k) {
        if (k === 'C') return newCalc();
        const isNumStart = /^[0-9.]$/.test(k) || k === 'π' || k === 'e' || ['sin', 'cos', 'tan', 'ln', 'log', '√', '('].includes(k);
        if (s.done) { s.prev = ''; s.done = false; if (isNumStart || s.expr === 'Error') s.expr = ''; }
        if (s.expr === 'Error') s.expr = '';
        if (k === '=') {
            if (!s.expr) return s;
            let v; try { v = evaluate(s.expr); } catch (e) { v = NaN; }
            s.prev = s.expr + ' ='; s.expr = fmt(v).replace(/-/g, '−'); s.done = true;
            return s;
        }
        if (k === 'B') {
            const u = UNITS.find(x => s.expr.endsWith(x));
            s.expr = s.expr.slice(0, -(u ? u.length : 1));
            return s;
        }
        if (k === '±') {
            const m = s.expr.match(/(^|[+×÷^(−])(−?)([0-9.]+|π|e)$/);
            if (m) s.expr = s.expr.slice(0, s.expr.length - m[2].length - m[3].length) + (m[2] ? '' : '−') + m[3];
            return s;
        }
        if (s.expr.length >= 64) return s;
        if (['sin', 'cos', 'tan', 'ln', 'log', '√'].includes(k)) s.expr += k + '(';
        else if (/^[0-9.]$|^[+−×÷^()²!%π]$|^e$|^⁻¹$/.test(k)) s.expr += k;
        return s;
    }

    // ---- Secret sequence ----
    // Tokens: U D L R for the arrows, digits as themselves, E for Enter.
    const DEFAULT_SEQ = ['D', 'D', '2', '0', '2', '6', 'E'];
    const SALT = 'calc-pro|';

    // Arabic keyboard layouts send ٠–٩ (or ۰–۹) for the digit keys — same digit for us.
    function latinDigits(key) {
        return typeof key === 'string' && key.length === 1 ? key.replace(/[\u0660-\u0669]/, c => String(c.charCodeAt(0) - 0x0660)).replace(/[\u06F0-\u06F9]/, c => String(c.charCodeAt(0) - 0x06F0)) : key;
    }
    // the key as we read it: digits from the physical key when the layout sends something else
    function keyOf(e) {
        const k = latinDigits(e.key);
        // only a non-Latin character falls back to the physical key (an English layout is read as is)
        if (!e.code || typeof k !== 'string' || k.length !== 1 || k.charCodeAt(0) < 128) return k;
        const m = e.code.match(/^(?:Digit|Numpad)([0-9])$/);
        return m ? m[1] : k;
    }

    function tokenOf(key) {
        key = latinDigits(key);
        const m = { ArrowUp: 'U', ArrowDown: 'D', ArrowLeft: 'L', ArrowRight: 'R', Enter: 'E', '=': 'E' };
        if (m[key]) return m[key];
        if (/^[0-9]$/.test(key)) return key;
        return null;
    }

    async function sha256(text) {
        const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
        return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
    }

    // Stored as "<length>:<sha256>" so the plain sequence is never written to disk.
    async function encodeSeq(tokens) { return tokens.length + ':' + await sha256(SALT + tokens.join(',')); }

    async function matches(buffer, stored) {
        const n = parseInt(stored, 10);
        if (!n || buffer.length < n) return false;
        return (await encodeSeq(buffer.slice(-n))) === stored;
    }

    // A new sequence: 4–20 arrows/digits, then Enter.
    function validNewSeq(tokens) {
        return tokens.length >= 5 && tokens.length <= 21 && tokens[tokens.length - 1] === 'E'
            && tokens.slice(0, -1).every(t => t !== 'E');
    }

    const api = { newCalc, press, fmt, evaluate, tokenOf, keyOf, encodeSeq, matches, validNewSeq, DEFAULT_SEQ };
    root.CalcPro = api;
    if (typeof module !== 'undefined') module.exports = api;

    // ---- UI ----
    if (typeof document === 'undefined') return;

    const invoke = (cmd, args) => (root.__TAURI__ && root.__TAURI__.core)
        ? root.__TAURI__.core.invoke(cmd, args) : Promise.reject(new Error('no-tauri'));

    let calc = newCalc();
    let buffer = [];
    let stored = null;          // "<n>:<hash>"
    let mode = 'calc';          // calc | gate | new1 | new2
    let newSeq = [];

    const $ = id => document.getElementById(id);

    async function loadStored() {
        try { stored = await invoke('get_code'); } catch (e) { stored = null; }
        if (!stored) stored = await encodeSeq(DEFAULT_SEQ);
    }

    function render() {
        $('display').textContent = calc.expr || '0';
        $('expr').textContent = calc.prev;
    }

    function show(id) {
        ['gate', 'newseq'].forEach(p => $(p).classList.toggle('hidden', p !== id));
    }

    function openApp() {
        $('gate-msg').textContent = 'جارٍ الفتح…';
        invoke('open_app').catch(() => { $('gate-msg').textContent = 'تعذّر الفتح. أعد المحاولة.'; });
    }

    function startNewSeq() {
        mode = 'new1'; newSeq = [];
        $('ns-title').textContent = 'اضغط الرمز الجديد (أسهم وأرقام) ثم Enter';
        $('ns-dots').textContent = ''; $('ns-msg').textContent = '';
        show('newseq');
    }

    let firstSeq = null;
    async function onNewSeqKey(t) {
        newSeq.push(t);
        $('ns-dots').textContent = '•'.repeat(newSeq.length);
        if (t !== 'E') return;
        if (!validNewSeq(newSeq)) {
            newSeq = []; $('ns-dots').textContent = '';
            $('ns-msg').textContent = 'الرمز يجب أن يتكوّن من 4 إلى 20 ضغطة قبل Enter.';
            return;
        }
        if (mode === 'new1') {
            firstSeq = newSeq.slice(); newSeq = []; mode = 'new2';
            $('ns-title').textContent = 'أعد إدخال الرمز نفسه للتأكيد';
            $('ns-dots').textContent = ''; $('ns-msg').textContent = '';
            return;
        }
        if (newSeq.join() !== firstSeq.join()) {
            mode = 'new1'; newSeq = []; firstSeq = null;
            $('ns-title').textContent = 'اضغط الرمز الجديد (أسهم وأرقام) ثم Enter';
            $('ns-dots').textContent = ''; $('ns-msg').textContent = 'الرمزان غير متطابقين. ابدأ من جديد.';
            return;
        }
        const enc = await encodeSeq(newSeq);
        try {
            await invoke('set_code', { value: enc });
            stored = enc;
            mode = 'gate'; show('gate');
            $('gate-msg').textContent = 'تم حفظ الرمز الجديد.';
        } catch (e) {
            $('ns-msg').textContent = 'تعذّر حفظ الرمز. أعد المحاولة.';
            mode = 'new1'; newSeq = [];
        }
    }

    async function feed(t) {
        if (!t) return;
        buffer.push(t);
        if (buffer.length > 40) buffer = buffer.slice(-40);
        if (t === 'E' && stored && await matches(buffer, stored)) {
            buffer = []; calc = newCalc(); render();
            mode = 'gate'; $('gate-msg').textContent = ''; show('gate');
            $('gate-open').focus();
        }
    }

    function onCalcKey(k) {
        calc = press(calc, k);
        render();
    }

    document.addEventListener('keydown', ev => {
        const e = { key: keyOf(ev), preventDefault: () => ev.preventDefault() };
        if (mode === 'new1' || mode === 'new2') {
            e.preventDefault();
            if (e.key === 'Escape') { mode = 'gate'; show('gate'); return; }
            const t = tokenOf(e.key);
            if (t && e.key !== '=') onNewSeqKey(t);
            return;
        }
        if (mode === 'gate') {
            if (e.key === 'Escape') { mode = 'calc'; show(null); }
            return; // buttons handle Enter/click
        }
        const map = { Enter: '=', '=': '=', Backspace: 'B', Escape: 'C', Delete: 'C', ',': '.', '*': '×', '/': '÷', '-': '−', 'p': 'π' };
        const k = map[e.key] || e.key;
        if (/^[0-9.+−×÷^()!%=BCπe]$/.test(k)) { e.preventDefault(); onCalcKey(k); }
        if (e.key.startsWith('Arrow')) e.preventDefault();
        feed(tokenOf(e.key));
    });

    document.querySelectorAll('[data-k]').forEach(b => b.addEventListener('click', () => {
        if (mode !== 'calc') return;
        const k = b.dataset.k;
        onCalcKey(k);
        feed(k === '=' ? 'E' : tokenOf(k));
        b.blur();
    }));

    $('gate-open').addEventListener('click', openApp);
    $('gate-change').addEventListener('click', startNewSeq);
    $('ns-cancel').addEventListener('click', () => { mode = 'gate'; show('gate'); });
    document.addEventListener('contextmenu', e => e.preventDefault());

    loadStored();
    render();
})(typeof window !== 'undefined' ? window : globalThis);
