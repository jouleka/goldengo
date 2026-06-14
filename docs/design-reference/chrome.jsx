// chrome.jsx — device frame, status bar, tab bar + Add FAB, toast (Goldengo warm chrome)
(function () {
  const Icon = window.Icon;

  function StatusBar() {
    // text/icons inherit currentColor = --ink
    return (
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 54, zIndex: 30,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '16px 30px 0', color: 'var(--ink)', pointerEvents: 'none',
      }}>
        <span style={{ fontSize: 16, fontWeight: 600, letterSpacing: .3, fontVariantNumeric: 'tabular-nums' }}>9:41</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <svg width="18" height="11" viewBox="0 0 18 11" fill="currentColor">
            <rect x="0" y="6.5" width="3" height="4.5" rx="0.7"/>
            <rect x="4.6" y="4.2" width="3" height="6.8" rx="0.7"/>
            <rect x="9.2" y="2" width="3" height="9" rx="0.7"/>
            <rect x="13.8" y="0" width="3" height="11" rx="0.7" opacity="0.35"/>
          </svg>
          <svg width="16" height="11" viewBox="0 0 16 11" fill="currentColor">
            <path d="M8 2.9c2.1 0 4 .8 5.4 2.2l1-1C12.7 2.4 10.5 1.4 8 1.4S3.3 2.4 1.6 4.1l1 1C4 3.7 5.9 2.9 8 2.9z"/>
            <path d="M8 6.1c1.2 0 2.3.5 3.1 1.3l1-1C12 5.3 10.1 4.6 8 4.6s-3 .7-4.1 1.8l1 1C5.7 6.6 6.8 6.1 8 6.1z"/>
            <circle cx="8" cy="9.4" r="1.3"/>
          </svg>
          <svg width="25" height="12" viewBox="0 0 25 12">
            <rect x="0.5" y="0.5" width="21" height="11" rx="3" stroke="currentColor" strokeOpacity="0.4" fill="none"/>
            <rect x="2" y="2" width="16" height="8" rx="1.6" fill="currentColor"/>
            <path d="M23 4v4c.8-.3 1.3-1 1.3-2S23.8 4.3 23 4z" fill="currentColor" fillOpacity="0.5"/>
          </svg>
        </div>
      </div>
    );
  }

  function GGDevice({ children, dark }) {
    return (
      <div className="gg-app" data-theme={dark ? 'dark' : 'light'} style={{
        width: 402, height: 874, borderRadius: 50, position: 'relative', overflow: 'hidden',
        background: 'var(--canvas)',
        boxShadow: '0 50px 90px rgba(40,30,10,0.28), 0 0 0 10px ' + (dark ? '#0c0a07' : '#e7ddca') + ', 0 0 0 11px rgba(0,0,0,0.25)',
      }}>
        <StatusBar />
        {/* dynamic island */}
        <div style={{
          position: 'absolute', top: 12, left: '50%', transform: 'translateX(-50%)',
          width: 122, height: 35, borderRadius: 22, background: '#000', zIndex: 40,
        }} />
        {children}
        {/* home indicator */}
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 135, height: 5, borderRadius: 100, zIndex: 60, pointerEvents: 'none',
          background: dark ? 'rgba(243,236,221,0.6)' : 'rgba(42,38,32,0.32)',
        }} />
      </div>
    );
  }

  // bottom tab bar: Home · (Add FAB) · Wallet
  function TabBar({ tab, onTab, onAdd }) {
    const item = (key, label, icon) => {
      const active = tab === key;
      return (
        <button className="gg-tabbar-btn" onClick={() => onTab(key)} style={{ width: 84 }}>
          <span style={{ color: active ? 'var(--accent)' : 'var(--ink-muted)' }}>
            <Icon name={icon} size={25} stroke={active ? 2 : 1.7} />
          </span>
          <span className="lbl" style={{ color: active ? 'var(--accent)' : 'var(--ink-muted)' }}>{label}</span>
        </button>
      );
    };
    return (
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 25,
        paddingBottom: 22, paddingTop: 10,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '10px 34px 24px',
        background: 'linear-gradient(to top, var(--canvas) 62%, color-mix(in srgb, var(--canvas) 0%, transparent))',
        borderTop: '1px solid transparent',
      }}>
        {item('home', 'Home', 'house')}
        {/* center Add FAB */}
        <button onClick={onAdd} aria-label="Add expense" style={{
          width: 62, height: 62, borderRadius: '50%', border: 'none', cursor: 'pointer',
          background: 'var(--accent)', color: 'var(--on-accent)',
          display: 'grid', placeItems: 'center', boxShadow: 'var(--shadow-fab)',
          marginTop: -22, transition: 'transform .14s cubic-bezier(.2,.8,.2,1)',
        }} onMouseDown={(e) => e.currentTarget.style.transform = 'scale(.92)'}
           onMouseUp={(e) => e.currentTarget.style.transform = 'scale(1)'}
           onMouseLeave={(e) => e.currentTarget.style.transform = 'scale(1)'}>
          <Icon name="plus" size={28} stroke={2.4} />
        </button>
        {item('wallet', 'Wallet', 'wallet.bifold')}
      </div>
    );
  }

  // top toast (Added / undo)
  function Toast({ text, icon, tint, actionLabel, onAction }) {
    return (
      <div style={{
        position: 'absolute', top: 64, left: '50%', transform: 'translateX(-50%)', zIndex: 70,
        animation: 'gg-toast-in .3s cubic-bezier(.2,.8,.2,1)',
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '11px 16px', borderRadius: 9999,
        background: 'var(--surface)', border: '1px solid var(--hairline)',
        boxShadow: '0 8px 24px rgba(40,30,10,0.18)',
        maxWidth: 320,
      }}>
        <span style={{ color: tint || 'var(--accent)', display: 'grid', placeItems: 'center' }}>
          <Icon name={icon || 'checkmark.circle'} size={20} stroke={2} />
        </span>
        <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--ink)', whiteSpace: 'nowrap' }}>{text}</span>
        {actionLabel && (
          <button onClick={onAction} style={{
            background: 'none', border: 'none', cursor: 'pointer', marginLeft: 4,
            color: 'var(--accent)', fontSize: 15, fontWeight: 700,
          }}>{actionLabel}</button>
        )}
      </div>
    );
  }

  Object.assign(window, { GGDevice, StatusBar, TabBar, Toast });
})();
