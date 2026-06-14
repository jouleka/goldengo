// home.jsx — Goldengo Home: wordmark, pocket hero, ghosts (usuals + due), recent
(function () {
  const { useState } = React;
  const Icon = window.Icon;
  const ICO = window.GG_ICON_FOR_CATEGORY;

  function Amt({ value, role = 'row', cls = '' }) {
    return <span className={`gg-amt gg-amt--${role} ${cls}`}>{value}</span>;
  }

  // a logged-expense / ghost row
  function Row({ icon, title, sub, right, rightColor, fundedBy, fundedColor, draft, onClick, recurring, accentRight }) {
    return (
      <button onClick={onClick} style={{
        width: '100%', background: 'none', border: 'none', cursor: onClick ? 'pointer' : 'default',
        display: 'flex', alignItems: 'center', gap: 14, padding: '9px 4px', textAlign: 'left',
        opacity: draft ? 0.72 : 1, WebkitTapHighlightColor: 'transparent',
      }}>
        <span className="gg-tile" style={{ color: 'var(--ink-muted)' }}><Icon name={icon} size={19} /></span>
        <span style={{ flex: 1, minWidth: 0 }}>
          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: 15.5, fontWeight: 500, color: 'var(--ink)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</span>
            {recurring && <span style={{ color: 'var(--ink-muted)' }}><Icon name="repeat" size={13} stroke={1.8} /></span>}
          </span>
          <span style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 2 }}>
            <span style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>{sub}</span>
            {fundedBy && (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '2px 8px', borderRadius: 9999, background: 'var(--field)' }}>
                <span style={{ width: 6, height: 6, borderRadius: 9999, background: `var(--src-${fundedColor})` }} />
                <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--ink-muted)' }}>{fundedBy}</span>
              </span>
            )}
          </span>
        </span>
        {accentRight
          ? <span style={{ color: 'var(--accent)' }}><Icon name="plus.circle" size={24} stroke={1.8} /></span>
          : <Amt value={right} role="row" cls={rightColor || ''} />}
      </button>
    );
  }

  function SectionHeader({ children, right }) {
    return (
      <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', margin: '22px 4px 6px' }}>
        <span className="gg-serif-header">{children}</span>
        {right}
      </div>
    );
  }

  function Home({ state, t, onConfirmGhost, onConfirmDue, onCycleDisplay, onOpenImport, onOpenSettings, onOpenExpense }) {
    const GG = window.GG;
    const dc = state.displayCurrency;
    const hasWallet = state.wallet.length > 0;

    // pocket hero — native cash (largest line), caption shows the rest
    const primary = state.wallet[0];
    const others = state.wallet.slice(1);
    const heroStr = primary ? GG.money(primary.expected, primary.code) : '—';
    const caption = others.length
      ? 'and ' + others.map(w => GG.money(w.expected, w.code)).join(' · ') + ' on hand'
      : 'cash you’re carrying right now';

    // today / month totals in display currency
    const sum = (when) => state.expenses
      .filter(e => when === 'month' ? true : e.when === 'today')
      .reduce((a, e) => a + GG.convert(e.amount, e.code, dc), 0);
    const todayTotal = GG.money(sum('today'), dc);
    const monthTotal = GG.money(sum('month'), dc);

    const todays = state.expenses.filter(e => e.when === 'today');
    const earlier = state.expenses.filter(e => e.when !== 'today');

    return (
      <div className="gg-scroll" style={{ position: 'absolute', inset: 0, paddingTop: 58, paddingBottom: 124, overflowX: 'hidden' }}>
        <div style={{ padding: '0 20px' }}>
          {/* header */}
          <div className="gg-rise" style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingTop: 14, paddingBottom: 8 }}>
            <span className="gg-wordmark" style={{ fontSize: 26 }}>Goldengo</span>
            <div style={{ display: 'flex', gap: 6 }}>
              <button onClick={onOpenImport} aria-label="Import statement" style={iconBtn}><Icon name="square.and.arrow.down" size={21} /></button>
              <button onClick={onOpenSettings} aria-label="Settings" style={iconBtn}><Icon name="gearshape" size={21} /></button>
            </div>
          </div>

          {/* pocket hero card */}
          <div className="gg-card gg-rise" style={{ padding: 22, animationDelay: '.04s' }}>
            <div className="gg-eyebrow">In your pocket</div>
            {hasWallet ? (
              <>
                <div style={{ marginTop: 10, marginBottom: 4 }} key={heroStr}>
                  <span className="gg-amt gg-amt--hero" style={{ animation: 'gg-tick .35s ease' }}>{heroStr}</span>
                </div>
                <div style={{ fontSize: 12.5, color: 'var(--ink-muted)' }}>{caption}</div>
              </>
            ) : (
              <div style={{ marginTop: 12, fontSize: 15, color: 'var(--ink-muted)' }}>Set your wallet to begin.</div>
            )}

            <hr className="gg-hr" style={{ margin: '18px 0' }} />

            <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between' }}>
              <div>
                <div className="gg-serif-header" style={{ fontSize: 16, marginBottom: 6 }}>This month</div>
                <button onClick={onCycleDisplay} style={{
                  display: 'inline-flex', alignItems: 'center', gap: 6, background: 'none', border: 'none',
                  padding: 0, cursor: 'pointer',
                }}>
                  <Amt value={monthTotal} role="title" />
                  <span style={{ color: 'var(--ink-muted)', marginTop: 4 }}><Icon name="chevron.down" size={13} stroke={2.2} /></span>
                </button>
              </div>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 12.5, color: 'var(--ink-muted)', marginBottom: 6 }}>Today</div>
                <Amt value={todayTotal} role="row" />
              </div>
            </div>
          </div>

          {/* due subscriptions */}
          {state.due.length > 0 && (
            <>
              <SectionHeader>Upcoming</SectionHeader>
              <div className="gg-rise" style={{ animationDelay: '.08s' }}>
                {state.due.map(d => (
                  <Row key={d.id} icon="repeat" title={d.name}
                       sub={`${GG.money(d.amount, d.code)} · ${d.dueLabel} · tap to add`}
                       draft accentRight onClick={() => onConfirmDue(d)} />
                ))}
              </div>
            </>
          )}

          {/* today's usuals (ghosts) */}
          {state.ghosts.length > 0 && (
            <>
              <SectionHeader>Today’s usuals</SectionHeader>
              <div className="gg-rise" style={{ animationDelay: '.1s' }}>
                {state.ghosts.map(g => (
                  <Row key={g.id} icon={ICO(g.category)} title={g.name}
                       sub={`~${GG.money(g.amount, g.code)} · tap to add`}
                       draft accentRight onClick={() => onConfirmGhost(g)} />
                ))}
              </div>
            </>
          )}

          {/* recent */}
          <SectionHeader>Recent</SectionHeader>
          {state.expenses.length === 0 ? (
            <div className="gg-card" style={{ padding: '28px 20px', textAlign: 'center' }}>
              <div style={{ color: 'var(--ink-muted)', display: 'grid', placeItems: 'center', marginBottom: 10 }}><Icon name="tag" size={26} /></div>
              <div style={{ fontSize: 15, fontWeight: 600 }}>No expenses yet</div>
              <div style={{ fontSize: 13, color: 'var(--ink-muted)', marginTop: 3 }}>Tap the gold button to log your first.</div>
            </div>
          ) : (
            <div className="gg-rise" style={{ animationDelay: '.12s' }}>
              {todays.map(e => <ExpenseRow key={e.id} e={e} onClick={() => onOpenExpense && onOpenExpense(e)} />)}
              {earlier.length > 0 && <div style={{ height: 8 }} />}
              {earlier.map(e => <ExpenseRow key={e.id} e={e} onClick={() => onOpenExpense && onOpenExpense(e)} />)}
            </div>
          )}
        </div>
      </div>
    );
  }

  function ExpenseRow({ e, onClick }) {
    const GG = window.GG;
    const ICO = window.GG_ICON_FOR_CATEGORY;
    return (
      <Row icon={ICO(e.category)} title={e.title} recurring={e.recurring}
           sub={e.category}
           fundedBy={e.sourceName} fundedColor={e.sourceColor}
           right={GG.money(e.amount, e.code)} onClick={onClick} />
    );
  }

  const iconBtn = {
    width: 36, height: 36, borderRadius: 9999, border: 'none', cursor: 'pointer',
    background: 'transparent', color: 'var(--ink-muted)', display: 'grid', placeItems: 'center',
    WebkitTapHighlightColor: 'transparent',
  };

  Object.assign(window, { Home, GGRow: Row, GGAmt: Amt, GGSectionHeader: SectionHeader });
})();
