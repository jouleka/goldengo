// income.jsx — Add income: amount + currency, cash-in-hand vs into a source, suggestion chips
(function () {
  const { useState } = React;
  const Icon = window.Icon;
  const GG = window.GG;
  const QA_CCYS = ['ALL', 'EUR', 'USD'];

  function AddIncome({ state, onClose, onSave }) {
    const [amount, setAmount] = useState('');
    const [code, setCode] = useState(state.displayCurrency || 'ALL');
    const [intoSource, setIntoSource] = useState(false);
    const [name, setName] = useState(null);
    const suggestions = ['Remittance', 'Pay', 'ATM', 'Cash gift', 'Refund'];
    const allowsDecimal = GG.decimalsFor(code) > 0;
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', allowsDecimal ? '.' : '', '0', '⌫'];

    function key(k) {
      if (window.ggBuzz) window.ggBuzz('tick');
      if (k === '⌫') return setAmount(a => a.slice(0, -1));
      if (k === '.') return setAmount(a => a.indexOf('.') >= 0 ? a : (a === '' ? '0.' : a + '.'));
      setAmount(a => {
        if (a.indexOf('.') >= 0 && a.split('.')[1].length >= GG.decimalsFor(code)) return a;
        if (a === '0') return k;
        return a + k;
      });
    }
    const value = parseFloat(amount || '0');
    const display = amount ? GG.money(value, code) : GG.symbolFor(code) + '0';
    const canSave = value > 0 && (!intoSource || name);

    return (
      <div style={{
        position: 'absolute', inset: 0, zIndex: 52, background: 'var(--canvas)',
        animation: 'gg-sheet-in .32s cubic-bezier(.2,.85,.25,1)',
        display: 'flex', flexDirection: 'column', padding: '0 22px 34px',
      }}>
        <div style={{ paddingTop: 50, position: 'relative', flexShrink: 0 }}>
          <div style={{ width: 38, height: 5, borderRadius: 9999, background: 'var(--hairline)', margin: '8px auto 0' }} />
          <button onClick={onClose} aria-label="Close" style={{
            position: 'absolute', right: 0, top: 50, width: 36, height: 36, borderRadius: 9999,
            background: 'var(--field)', border: 'none', cursor: 'pointer', color: 'var(--ink-muted)',
            display: 'grid', placeItems: 'center',
          }}><Icon name="chevron.down" size={20} stroke={2.2} /></button>
        </div>

        <div style={{ textAlign: 'center', paddingTop: 16 }}>
          <div className="gg-serif-title" style={{ fontSize: 22, color: 'var(--ink-muted)', marginBottom: 14 }}>Money in</div>
          <div style={{ display: 'inline-flex', alignItems: 'baseline', gap: 6 }}>
            <CcyMini code={code} onCcy={setCode} />
            <span className="gg-amt" key={display} style={{ fontSize: 48, letterSpacing: '-2px', color: amount ? 'var(--income)' : 'var(--ink-muted)' }}>
              <span style={{ animation: 'gg-tick .28s ease' }}>{display}</span>
            </span>
          </div>
        </div>

        {/* destination */}
        <div style={{ display: 'flex', gap: 8, marginTop: 22, background: 'var(--field)', padding: 4, borderRadius: 'var(--r-control)' }}>
          {[['Cash in hand', false], ['Into a source', true]].map(([lbl, v]) => (
            <button key={lbl} onClick={() => setIntoSource(v)} style={{
              flex: 1, padding: '9px', borderRadius: 12, border: 'none', cursor: 'pointer',
              fontSize: 14, fontWeight: 600,
              background: intoSource === v ? 'var(--surface)' : 'transparent',
              color: intoSource === v ? 'var(--ink)' : 'var(--ink-muted)',
              boxShadow: intoSource === v ? '0 1px 3px rgba(40,30,10,0.12)' : 'none',
            }}>{lbl}</button>
          ))}
        </div>
        {intoSource && (
          <div className="gg-scroll" style={{ display: 'flex', gap: 8, marginTop: 12, overflowX: 'auto', paddingBottom: 2 }}>
            {suggestions.map(s => (
              <button key={s} className={'gg-chip' + (name === s ? ' is-selected' : '')} onClick={() => setName(name === s ? null : s)}>{s}</button>
            ))}
          </div>
        )}

        <div style={{ flex: 1, minHeight: 10 }} />

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 9, marginBottom: 14 }}>
          {keys.map((k, i) => k === '' ? <span key={i} /> : (
            <button key={i} className="gg-key" style={{ height: 54 }} onClick={() => key(k)}>
              {k === '⌫' ? <Icon name="delete.left" size={26} stroke={1.7} /> : k}
            </button>
          ))}
        </div>
        <button className="gg-btn" disabled={!canSave} onClick={() => onSave({ amount: value, code, intoSource, name })}>Add income</button>
      </div>
    );
  }

  function CcyMini({ code, onCcy }) {
    const [open, setOpen] = useState(false);
    return (
      <span style={{ position: 'relative' }}>
        <button onClick={() => setOpen(o => !o)} style={{ background: 'none', border: 'none', cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 1, color: 'var(--ink-muted)' }}>
          <span style={{ fontSize: 28, fontWeight: 600 }}>{GG.symbolFor(code)}</span>
          <span style={{ marginTop: 5 }}><Icon name="chevron.down" size={11} stroke={2.4} /></span>
        </button>
        {open && (
          <>
            <div onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 80 }} />
            <div style={{ position: 'absolute', top: 'calc(100% + 8px)', left: '50%', transform: 'translateX(-50%)', zIndex: 81, background: 'var(--surface)', border: '1px solid var(--hairline)', borderRadius: 14, boxShadow: '0 10px 30px rgba(40,30,10,0.2)', padding: 5, minWidth: 150, animation: 'gg-pop-in .16s ease' }}>
              {QA_CCYS.map(c => (
                <button key={c} onClick={() => { onCcy(c); setOpen(false); }} style={{ display: 'flex', alignItems: 'center', gap: 10, width: '100%', textAlign: 'left', background: 'none', border: 'none', cursor: 'pointer', padding: '9px 12px', borderRadius: 10, color: 'var(--ink)', fontSize: 15 }}>
                  <span style={{ width: 16, fontWeight: 700, color: 'var(--ink-muted)' }}>{GG.symbolFor(c)}</span>
                  <span style={{ flex: 1 }}>{GG.nameFor(c)}</span>
                  {c === code && <span style={{ color: 'var(--accent)' }}><Icon name="checkmark" size={15} stroke={2.4} /></span>}
                </button>
              ))}
            </div>
          </>
        )}
      </span>
    );
  }

  window.AddIncome = AddIncome;
})();
