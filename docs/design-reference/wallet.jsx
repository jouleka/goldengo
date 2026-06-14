// wallet.jsx — Wallet tab: per-currency cash + draining Sources pools + adjust sheet + add income
(function () {
  const { useState } = React;
  const Icon = window.Icon;
  const GG = window.GG;

  function label(code) {
    return code === 'ALL' ? 'Lek (ALL)' : `${GG.nameFor(code)} (${code})`;
  }

  function Wallet({ state, t, onAdjust, onAddIncome, onAddCcy }) {
    const sources = state.sources;
    const hasWallet = state.wallet.length > 0;
    return (
      <div className="gg-scroll" style={{ position: 'absolute', inset: 0, paddingTop: 58, paddingBottom: 124, overflowX: 'hidden' }}>
        <div style={{ padding: '0 20px' }}>
          {/* large serif title */}
          <div className="gg-rise" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '18px 4px 14px' }}>
            <span className="gg-serif-title" style={{ fontSize: 32 }}>Wallet</span>
            <button onClick={onAddIncome} style={{
              display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 14px', borderRadius: 9999,
              background: 'var(--accent-soft)', border: '1px solid var(--accent-line)', cursor: 'pointer',
              color: 'var(--accent)', fontSize: 14, fontWeight: 600,
            }}>
              <Icon name="plus" size={15} stroke={2.4} /> Income
            </button>
          </div>

          {/* in your wallet — cash lines */}
          <div className="gg-card gg-rise" style={{ padding: '6px 6px', animationDelay: '.04s' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '14px 16px 10px' }}>
              <span style={{ color: 'var(--accent)' }}><Icon name="wallet.bifold" size={19} /></span>
              <span className="gg-eyebrow" style={{ color: 'var(--ink-muted)' }}>In your wallet</span>
            </div>
            {hasWallet ? state.wallet.map((w, i) => (
              <button key={w.code} onClick={() => onAdjust(w.code)} style={{
                width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                background: 'none', border: 'none', cursor: 'pointer', padding: '12px 16px', textAlign: 'left',
                borderTop: i === 0 ? 'none' : '1px solid var(--hairline)',
              }}>
                <span style={{ fontSize: 15.5, fontWeight: 600, color: 'var(--ink)' }}>{label(w.code)}</span>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                  <span className="gg-amt gg-amt--row">~{GG.money(w.expected, w.code)}</span>
                  <span style={{ color: 'var(--ink-muted)' }}><Icon name="chevron.right" size={15} stroke={2} /></span>
                </span>
              </button>
            )) : (
              <div style={{ padding: '4px 16px 16px', fontSize: 13.5, color: 'var(--ink-muted)' }}>
                Your pocket, by currency. Tap below to set what you’re actually holding.
              </div>
            )}
            <button onClick={onAddCcy} style={{
              width: '100%', display: 'flex', alignItems: 'center', gap: 9, color: 'var(--ink-muted)',
              background: 'none', border: 'none', borderTop: '1px solid var(--hairline)', cursor: 'pointer',
              padding: '13px 16px', fontSize: 14.5, fontWeight: 500,
            }}>
              <Icon name="plus.circle" size={18} stroke={1.8} /> Track another currency
            </button>
          </div>
          <div style={{ padding: '8px 6px 0', fontSize: 12, color: 'var(--ink-muted)' }}>
            Cash spends drain this — not your sources. Reconcile by feel.
          </div>

          {/* sources — draining pools */}
          <div className="gg-serif-header" style={{ margin: '26px 4px 12px' }}>Sources</div>
          {sources.length === 0 ? (
            <div className="gg-card" style={{ padding: '26px 20px', textAlign: 'center' }}>
              <div style={{ color: 'var(--ink-muted)', display: 'grid', placeItems: 'center', marginBottom: 10 }}><Icon name="banknote" size={26} /></div>
              <div style={{ fontSize: 15, fontWeight: 600 }}>No sources yet</div>
              <div style={{ fontSize: 13, color: 'var(--ink-muted)', marginTop: 4, lineHeight: 1.45 }}>Add where money came from — a remittance, a cash withdrawal, your pay.</div>
            </div>
          ) : (
            <div className="gg-rise" style={{ display: 'flex', flexDirection: 'column', gap: 12, animationDelay: '.08s' }}>
              {sources.map(s => {
                const frac = Math.max(0, Math.min(1, s.remaining / s.inflow));
                return (
                  <div key={s.id} className="gg-card" style={{ padding: 18 }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 9 }}>
                        <span style={{ width: 10, height: 10, borderRadius: 9999, background: `var(--src-${s.colorIndex})` }} />
                        <span style={{ fontSize: 15.5, fontWeight: 600 }}>{s.name}</span>
                      </span>
                      <span className="gg-amt gg-amt--row">{GG.money(s.remaining, s.code)}</span>
                    </div>
                    <div className="gg-pool"><i style={{ width: `${frac * 100}%`, background: `var(--src-${s.colorIndex})` }} /></div>
                    <div style={{ marginTop: 9, fontSize: 12, color: 'var(--ink-muted)' }}>
                      {GG.money(s.remaining, s.code)} of {GG.money(s.inflow, s.code)} left · {Math.round(frac * 100)}%
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    );
  }

  // ---------- Adjust sheet: count what's in your pocket ----------
  function AdjustSheet({ state, code, onClose, onSave }) {
    const line = state.wallet.find(w => w.code === code);
    const expected = line ? line.expected : null;
    const [amount, setAmount] = useState(expected != null ? String(expected) : '');
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
    const f = amount ? amount.replace(/\B(?=(\d{3})+(?!\d))/g, x => x) : '0';
    const display = amount ? GG.money(value, code) : GG.symbolFor(code) + '0';
    const gap = expected != null ? value - expected : 0;

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

        <div style={{ paddingTop: 22 }}>
          <div className="gg-serif-title" style={{ fontSize: 25 }}>What’s in your wallet?</div>
          {expected != null && (
            <div style={{ fontSize: 13.5, color: 'var(--ink-muted)', marginTop: 6 }}>
              The books expect {GG.money(expected, code)}. Count it and set what’s real.
            </div>
          )}
        </div>

        <div style={{ flex: 1, display: 'grid', placeItems: 'center' }}>
          <span className="gg-amt" key={display} style={{ fontSize: 52, letterSpacing: '-2px' }}>
            <span style={{ animation: 'gg-tick .28s ease' }}>{display}</span>
          </span>
        </div>

        {expected != null && value > 0 && Math.abs(gap) > (code === 'ALL' ? 0 : 0.001) && (
          <div style={{ textAlign: 'center', marginBottom: 14, fontSize: 12.5, color: 'var(--ink-muted)' }}>
            {gap < 0
              ? `${GG.money(-gap, code)} less than expected → logged as Unaccounted`
              : `${GG.money(gap, code)} more than expected — that’s fine`}
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 9, marginBottom: 14 }}>
          {keys.map((k, i) => k === '' ? <span key={i} /> : (
            <button key={i} className="gg-key" style={{ height: 56 }} onClick={() => key(k)}>
              {k === '⌫' ? <Icon name="delete.left" size={26} stroke={1.7} /> : k}
            </button>
          ))}
        </div>
        <button className="gg-btn" disabled={value <= 0} onClick={() => onSave(code, value)}>Save</button>
      </div>
    );
  }

  Object.assign(window, { Wallet, AdjustSheet });
})();
