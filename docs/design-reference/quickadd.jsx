// quickadd.jsx — the 2-second log. Three layout variations (stacked / padfirst / grid).
(function () {
  const { useState, useRef } = React;
  const Icon = window.Icon;
  const ICO = window.GG_ICON_FOR_CATEGORY;
  const GG = window.GG;

  const QA_CCYS = ['ALL', 'EUR', 'USD'];

  function formatTyped(str, code) {
    const sym = GG.symbolFor(code);
    if (!str) return { sym, body: '0', muted: true };
    let [int, dec] = str.split('.');
    int = int || '0';
    const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    let body = grouped;
    if (str.indexOf('.') >= 0) body += '.' + (dec || '');
    return { sym, body, muted: false };
  }

  // ---------- shared sub-components ----------
  function AmountBlock({ amount, code, onCcy, big }) {
    const f = formatTyped(amount, code);
    const base = big ? 56 : 50;
    const len = f.body.length;
    const heroSize = len <= 7 ? base : Math.max(30, Math.round(base * 7 / len));
    return (
      <div style={{ textAlign: 'center' }}>
        <div className="gg-serif-title" style={{ fontSize: 19, color: 'var(--ink-muted)', marginBottom: 14 }}>New expense</div>
        <div style={{ display: 'inline-flex', alignItems: 'baseline', gap: 6, justifyContent: 'center', maxWidth: '100%' }}>
          <CurrencyMenu code={code} onCcy={onCcy} />
          <span className="gg-amt" style={{
            fontSize: heroSize, letterSpacing: '-2px', lineHeight: 1,
            color: f.muted ? 'var(--ink-muted)' : 'var(--ink)',
            transition: 'color .2s ease, font-size .15s ease',
          }} key={f.body}>
            <span style={{ animation: 'gg-tick .28s cubic-bezier(.2,.8,.2,1)' }}>{f.body}</span>
          </span>
        </div>
      </div>
    );
  }

  function CurrencyMenu({ code, onCcy }) {
    const [open, setOpen] = useState(false);
    const sym = GG.symbolFor(code);
    return (
      <span style={{ position: 'relative' }}>
        <button onClick={() => setOpen(o => !o)} style={{
          background: 'none', border: 'none', cursor: 'pointer', padding: '0 2px',
          display: 'inline-flex', alignItems: 'center', gap: 1, color: 'var(--ink-muted)',
        }}>
          <span style={{ fontSize: 30, fontWeight: 600 }}>{sym}</span>
          <span style={{ marginTop: 6 }}><Icon name="chevron.down" size={12} stroke={2.4} /></span>
        </button>
        {open && (
          <>
            <div onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 80 }} />
            <div style={{
              position: 'absolute', top: 'calc(100% + 8px)', left: '50%', transform: 'translateX(-50%)', zIndex: 81,
              background: 'var(--surface)', border: '1px solid var(--hairline)', borderRadius: 14,
              boxShadow: '0 10px 30px rgba(40,30,10,0.2)', padding: 5, minWidth: 160,
              animation: 'gg-pop-in .16s cubic-bezier(.2,.8,.2,1)',
            }}>
              {QA_CCYS.map(c => (
                <button key={c} onClick={() => { onCcy(c); setOpen(false); }} style={{
                  display: 'flex', alignItems: 'center', gap: 10, width: '100%', textAlign: 'left',
                  background: 'none', border: 'none', cursor: 'pointer', padding: '9px 12px', borderRadius: 10,
                  color: 'var(--ink)', fontSize: 15,
                }}>
                  <span style={{ width: 18, fontWeight: 700, color: 'var(--ink-muted)' }}>{GG.symbolFor(c)}</span>
                  <span style={{ flex: 1 }}>{GG.nameFor(c)}</span>
                  {c === code && <span style={{ color: 'var(--accent)' }}><Icon name="checkmark" size={16} stroke={2.4} /></span>}
                </button>
              ))}
            </div>
          </>
        )}
      </span>
    );
  }

  function Chips({ cats, selected, onSelect, wrap }) {
    return (
      <div className={wrap ? '' : 'gg-scroll'} style={wrap
        ? { display: 'flex', flexWrap: 'wrap', gap: 9, justifyContent: 'center' }
        : { display: 'flex', gap: 9, overflowX: 'auto', padding: '2px 0' }}>
        {cats.map(c => (
          <button key={c} className={'gg-chip' + (selected === c ? ' is-selected' : '')}
                  onClick={() => onSelect(selected === c ? null : c)}>
            <span className="gg-chip-ico" style={{ color: selected === c ? 'var(--accent)' : 'var(--ink-muted)' }}>
              <Icon name={ICO(c)} size={16} stroke={1.8} />
            </span>
            {c}
          </button>
        ))}
      </div>
    );
  }

  function PaidFrom({ sources, value, onChange, code }) {
    const [open, setOpen] = useState(false);
    const sel = sources.find(s => s.id === value);
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span className="gg-eyebrow">Paid from</span>
        <span style={{ position: 'relative' }}>
          <button onClick={() => setOpen(o => !o)} style={{
            display: 'inline-flex', alignItems: 'center', gap: 8, padding: '8px 14px', borderRadius: 9999,
            background: 'var(--field)', border: 'none', cursor: 'pointer', color: 'var(--ink)',
          }}>
            {sel
              ? <span style={{ width: 9, height: 9, borderRadius: 9999, background: `var(--src-${sel.colorIndex})` }} />
              : <span style={{ color: 'var(--ink-muted)' }}><Icon name="wallet.bifold" size={16} /></span>}
            <span style={{ fontSize: 14.5, fontWeight: 600 }}>{sel ? sel.name : 'Wallet — cash'}</span>
            <span style={{ color: 'var(--ink-muted)' }}><Icon name="chevron.down" size={12} stroke={2.2} /></span>
          </button>
          {open && (
            <>
              <div onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 80 }} />
              <div style={{
                position: 'absolute', bottom: 'calc(100% + 8px)', right: 0, zIndex: 81, minWidth: 220,
                background: 'var(--surface)', border: '1px solid var(--hairline)', borderRadius: 14,
                boxShadow: '0 10px 30px rgba(40,30,10,0.2)', padding: 5,
                animation: 'gg-pop-in .16s cubic-bezier(.2,.8,.2,1)',
              }}>
                <PFItem active={!value} onClick={() => { onChange(null); setOpen(false); }}
                        dot={<Icon name="wallet.bifold" size={16} />} label="Wallet — cash" />
                {sources.map(s => (
                  <PFItem key={s.id} active={value === s.id} onClick={() => { onChange(s.id); setOpen(false); }}
                          dot={<span style={{ width: 9, height: 9, borderRadius: 9999, background: `var(--src-${s.colorIndex})` }} />}
                          label={s.name} note={`${GG.money(s.remaining, s.code)} left`} />
                ))}
              </div>
            </>
          )}
        </span>
      </div>
    );
  }
  function PFItem({ active, onClick, dot, label, note }) {
    return (
      <button onClick={onClick} style={{
        display: 'flex', alignItems: 'center', gap: 10, width: '100%', textAlign: 'left',
        background: 'none', border: 'none', cursor: 'pointer', padding: '9px 12px', borderRadius: 10, color: 'var(--ink)',
      }}>
        <span style={{ width: 18, display: 'grid', placeItems: 'center', color: 'var(--ink-muted)' }}>{dot}</span>
        <span style={{ flex: 1, fontSize: 14.5 }}>{label}</span>
        {note && <span style={{ fontSize: 12, color: 'var(--ink-muted)' }}>{note}</span>}
        {active && <span style={{ color: 'var(--accent)', marginLeft: 6 }}><Icon name="checkmark" size={16} stroke={2.4} /></span>}
      </button>
    );
  }

  function Keypad({ code, onKey, keyH }) {
    const allowsDecimal = GG.decimalsFor(code) > 0;
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', allowsDecimal ? '.' : '', '0', '⌫'];
    return (
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 9 }}>
        {keys.map((k, i) => k === '' ? <span key={i} /> : (
          <button key={i} className="gg-key" style={{ height: keyH }} onClick={() => onKey(k)}>
            {k === '⌫' ? <Icon name="delete.left" size={26} stroke={1.7} /> : k}
          </button>
        ))}
      </div>
    );
  }

  function ScanBtn({ onClick }) {
    return (
      <button onClick={onClick} style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, width: '100%',
        background: 'none', border: 'none', cursor: 'pointer', color: 'var(--accent)',
        fontSize: 15, fontWeight: 600, padding: '6px 0', minHeight: 40,
      }}>
        <Icon name="doc.viewfinder" size={19} stroke={1.8} /> Scan receipt
      </button>
    );
  }

  // ---------- the sheet ----------
  function QuickAdd({ state, t, onClose, onSave, onScan }) {
    const [amount, setAmount] = useState('');
    const [code, setCode] = useState(state.displayCurrency || 'ALL');
    const [category, setCategory] = useState(null);
    const [source, setSource] = useState(null);
    const cats = GG.QUICK_CATEGORIES;
    const sources = state.sources;
    const layout = t.qaLayout || 'stacked';
    const keyH = { compact: 52, regular: 60, comfy: 68 }[t.qaDensity || 'regular'];

    function onKey(k) {
      if (window.ggBuzz) window.ggBuzz('tick');
      if (k === '⌫') { setAmount(a => a.slice(0, -1)); return; }
      setAmount(a => {
        if (k === '.') { if (a.indexOf('.') >= 0 || a === '') return a === '' ? '0.' : a; return a + '.'; }
        // limit decimals
        const dec = GG.decimalsFor(code);
        if (a.indexOf('.') >= 0 && a.split('.')[1].length >= dec) return a;
        if (a === '0') return k; // replace leading zero
        if (a.length >= 9) return a;
        return a + k;
      });
    }
    function changeCcy(c) {
      setCode(c);
      // trim decimals if new currency has none
      if (GG.decimalsFor(c) === 0) setAmount(a => a.split('.')[0]);
    }
    const value = parseFloat(amount || '0');
    const canSave = value > 0;
    function save() {
      if (!canSave) return;
      const src = sources.find(s => s.id === source);
      onSave({
        amount: value, code, category: category || 'Other', source: source || null,
        sourceName: src ? src.name : null, sourceColor: src ? src.colorIndex : null,
      });
    }

    return (
      <div style={{
        position: 'absolute', inset: 0, zIndex: 50, background: 'var(--canvas)',
        animation: 'gg-sheet-in .34s cubic-bezier(.2,.85,.25,1)',
        display: 'flex', flexDirection: 'column',
      }}>
        {/* grab + close */}
        <div style={{ paddingTop: 50, position: 'relative', flexShrink: 0 }}>
          <div style={{ width: 38, height: 5, borderRadius: 9999, background: 'var(--hairline)', margin: '8px auto 0' }} />
          <button onClick={onClose} aria-label="Close" style={{
            position: 'absolute', right: 16, top: 50, width: 36, height: 36, borderRadius: 9999,
            background: 'var(--field)', border: 'none', cursor: 'pointer', color: 'var(--ink-muted)',
            display: 'grid', placeItems: 'center',
          }}><Icon name="chevron.down" size={20} stroke={2.2} /></button>
        </div>

        {layout === 'stacked' && (
          <StackedLayout {...{ amount, code, changeCcy, cats, category, setCategory, sources, source, setSource, onKey, keyH, canSave, save, onScan }} />
        )}
        {layout === 'padfirst' && (
          <PadFirstLayout {...{ amount, code, changeCcy, cats, category, setCategory, sources, source, setSource, onKey, keyH, canSave, save, onScan }} />
        )}
        {layout === 'grid' && (
          <GridLayout {...{ amount, code, changeCcy, cats, category, setCategory, sources, source, setSource, onKey, keyH, canSave, save, onScan }} />
        )}
      </div>
    );
  }

  // --- Layout A: Stacked (classic) ---
  function StackedLayout(p) {
    return (
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '14px 22px 34px', overflow: 'hidden' }}>
        <div style={{ paddingTop: 8 }}><AmountBlock amount={p.amount} code={p.code} onCcy={p.changeCcy} /></div>
        <div style={{ marginTop: 22 }}><Chips cats={p.cats} selected={p.category} onSelect={p.setCategory} /></div>
        {p.sources.length > 0 && <div style={{ marginTop: 16 }}><PaidFrom sources={p.sources} value={p.source} onChange={p.setSource} code={p.code} /></div>}
        <div style={{ flex: 1 }} />
        <div style={{ marginTop: 16 }}><Keypad code={p.code} onKey={p.onKey} keyH={p.keyH} /></div>
        <div style={{ marginTop: 10 }}><ScanBtn onClick={p.onScan} /></div>
        <div style={{ marginTop: 8 }}>
          <button className="gg-btn" disabled={!p.canSave} onClick={p.save}>Add expense</button>
        </div>
      </div>
    );
  }

  // --- Layout B: Pad-first (one-thumb speed) — dominant numpad, condensed chrome ---
  function PadFirstLayout(p) {
    return (
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '10px 20px 34px', overflow: 'hidden' }}>
        <div style={{ paddingTop: 4 }}><AmountBlock amount={p.amount} code={p.code} onCcy={p.changeCcy} big /></div>
        <div style={{ marginTop: 16 }}>
          <Chips cats={p.cats} selected={p.category} onSelect={p.setCategory} />
        </div>
        <div style={{ flex: 1, minHeight: 8 }} />
        <div style={{ marginBottom: 12, display: 'flex', justifyContent: p.sources.length ? 'space-between' : 'flex-end', alignItems: 'center' }}>
          {p.sources.length > 0 && <PaidFrom sources={p.sources} value={p.source} onChange={p.setSource} code={p.code} />}
        </div>
        <Keypad code={p.code} onKey={p.onKey} keyH={p.keyH + 4} />
        <div style={{ marginTop: 12, display: 'flex', gap: 10, alignItems: 'center' }}>
          <button onClick={p.onScan} aria-label="Scan receipt" style={{
            width: 56, height: 54, borderRadius: 'var(--r-control)', flexShrink: 0,
            background: 'var(--field)', border: 'none', cursor: 'pointer', color: 'var(--accent)',
            display: 'grid', placeItems: 'center',
          }}><Icon name="doc.viewfinder" size={22} stroke={1.8} /></button>
          <button className="gg-btn" disabled={!p.canSave} onClick={p.save} style={{ flex: 1 }}>Add</button>
        </div>
      </div>
    );
  }

  // --- Layout C: Category-grid (tap category first, prominent grid) ---
  function GridLayout(p) {
    return (
      <div className="gg-scroll" style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '14px 22px 34px' }}>
        <div style={{ paddingTop: 6 }}><AmountBlock amount={p.amount} code={p.code} onCcy={p.changeCcy} /></div>
        <div style={{ marginTop: 24, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10 }}>
          {p.cats.map(c => {
            const on = p.category === c;
            return (
              <button key={c} onClick={() => p.setCategory(on ? null : c)} style={{
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, padding: '16px 6px',
                borderRadius: 'var(--r-control)', cursor: 'pointer',
                background: on ? 'var(--accent-soft)' : 'var(--field)',
                border: '1px solid ' + (on ? 'var(--accent-line)' : 'transparent'),
                color: 'var(--ink)', transition: 'transform .12s ease, background .16s ease, border-color .16s ease',
              }}>
                <span style={{ color: on ? 'var(--accent)' : 'var(--ink-muted)' }}><Icon name={ICO(c)} size={24} stroke={1.7} /></span>
                <span style={{ fontSize: 13, fontWeight: 600 }}>{c}</span>
              </button>
            );
          })}
        </div>
        {p.sources.length > 0 && <div style={{ marginTop: 18 }}><PaidFrom sources={p.sources} value={p.source} onChange={p.setSource} code={p.code} /></div>}
        <div style={{ marginTop: 18 }}><Keypad code={p.code} onKey={p.onKey} keyH={p.keyH} /></div>
        <div style={{ marginTop: 10 }}><ScanBtn onClick={p.onScan} /></div>
        <div style={{ marginTop: 8 }}>
          <button className="gg-btn" disabled={!p.canSave} onClick={p.save}>Add expense</button>
        </div>
      </div>
    );
  }

  Object.assign(window, { QuickAdd });
})();
