// icons.jsx — minimal SF-symbol-flavored line glyphs. currentColor, 1.7 stroke.
// <Icon name="cart" size={20} />
(function () {
  const P = (d, extra) => ({ d, ...extra });
  // each entry: array of <path>/<circle> spec objects, drawn in a 24x24 viewbox
  const G = {
    cart: { s: [P("M3 4h2l2.4 11.2a1.5 1.5 0 0 0 1.48 1.18h7.7a1.5 1.5 0 0 0 1.46-1.14L21 8H6.2")], c:[["9.5",20,1.4],["18",20,1.4]] },
    'fork.knife': { s: [P("M6 3v7a2 2 0 0 0 4 0V3M8 10v11"), P("M16 3c-1.5 0-2.5 2-2.5 5s1 4 2.5 4 2.5-1 2.5-4-1-5-2.5-5zM16 12v9")] },
    car: { s: [P("M5 11l1.6-4.2A2 2 0 0 1 8.5 5.5h7a2 2 0 0 1 1.9 1.3L19 11M4 11h16v5a1 1 0 0 1-1 1h-1.5v1.5a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1V17H9.5v1.5a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1V17H5a1 1 0 0 1-1-1z")], c:[["7.5",14,0.9],["16.5",14,0.9]] },
    'cup.and.saucer': { s: [P("M5 8h11v5a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4zM16 9h2.5a2 2 0 0 1 0 4H16M4 21h13"), P("M8 3.5c-.6.8-.6 1.6 0 2.4M11.5 3.5c-.6.8-.6 1.6 0 2.4")] },
    'doc.text': { s: [P("M7 3h7l4 4v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM14 3v4h4M9 12h7M9 16h7M9 8h2")] },
    bag: { s: [P("M6 8h12l-.8 11a1.5 1.5 0 0 1-1.5 1.4H8.3a1.5 1.5 0 0 1-1.5-1.4zM9 8V6.5a3 3 0 0 1 6 0V8")] },
    tag: { s: [P("M4 11.5V5a1 1 0 0 1 1-1h6.5a2 2 0 0 1 1.4.6l6.5 6.5a2 2 0 0 1 0 2.8l-6.6 6.6a2 2 0 0 1-2.8 0L4.6 13a2 2 0 0 1-.6-1.5z")], c:[["8",8,1.2]] },
    plus: { s: [P("M12 5v14M5 12h14")] },
    'plus.circle': { s: [P("M12 8v8M8 12h8")], c:[["12",12,9]] },
    'delete.left': { s: [P("M9 5h10a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H9l-6-7zM14 9l-4 6M10 9l4 6")] },
    'chevron.down': { s: [P("M5 9l7 7 7-7")] },
    'chevron.right': { s: [P("M9 5l7 7-7 7")] },
    'chevron.left': { s: [P("M15 5l-7 7 7 7")] },
    repeat: { s: [P("M4 8h12a4 4 0 0 1 4 4M7 5L4 8l3 3M20 16H8a4 4 0 0 1-4-4M17 19l3-3-3-3")] },
    'wallet.bifold': { s: [P("M4 7a2 2 0 0 1 2-2h11a1 1 0 0 1 1 1v3M4 7v10a2 2 0 0 0 2 2h12a1 1 0 0 0 1-1v-3M4 7h14a2 2 0 0 1 2 2v3")], c:[["16.5",13,1.2]] },
    checkmark: { s: [P("M5 13l4 4L19 6")] },
    'checkmark.circle': { s: [P("M8.5 12.5l2.5 2.5 4.5-5")], c:[["12",12,9]] },
    'doc.viewfinder': { s: [P("M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M9 9h6v6H9z")] },
    'sun.max': { s: [P("M12 4V2M12 22v-2M4 12H2M22 12h-2M5.6 5.6L4.2 4.2M19.8 19.8l-1.4-1.4M18.4 5.6l1.4-1.4M4.2 19.8l1.4-1.4")], c:[["12",12,4]] },
    moon: { s: [P("M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z")] },
    gearshape: { s: [P("M10.4 3.2a1 1 0 0 1 1-.8h1.2a1 1 0 0 1 1 .8l.3 1.6a7 7 0 0 1 1.7 1l1.5-.6a1 1 0 0 1 1.2.4l.6 1a1 1 0 0 1-.2 1.3l-1.3 1a7 7 0 0 1 0 2l1.3 1a1 1 0 0 1 .2 1.3l-.6 1a1 1 0 0 1-1.2.4l-1.5-.6a7 7 0 0 1-1.7 1l-.3 1.6a1 1 0 0 1-1 .8h-1.2a1 1 0 0 1-1-.8l-.3-1.6a7 7 0 0 1-1.7-1l-1.5.6a1 1 0 0 1-1.2-.4l-.6-1a1 1 0 0 1 .2-1.3l1.3-1a7 7 0 0 1 0-2l-1.3-1a1 1 0 0 1-.2-1.3l.6-1a1 1 0 0 1 1.2-.4l1.5.6a7 7 0 0 1 1.7-1z")], c:[["12",12,2.6]] },
    'square.and.arrow.down': { s: [P("M12 3v11M8 10l4 4 4-4M5 14v3a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-3")] },
    house: { s: [P("M4 11l8-7 8 7M6 9.5V19a1 1 0 0 0 1 1h3v-5h4v5h3a1 1 0 0 0 1-1V9.5")] },
    'arrow.triangle': { s: [P("M4 8h12a4 4 0 0 1 4 4M7 5L4 8l3 3M20 16H8a4 4 0 0 1-4-4M17 19l3-3-3-3")] },
    'banknote': { s: [P("M3 7h18a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1zM2 10h2M22 14h-2")], c:[["12",12,2.4]] },
    'questionmark.circle': { s: [P("M9.5 9.5a2.5 2.5 0 0 1 4.8.8c0 1.7-2.3 2-2.3 3.7"), P("")], c:[["12",12,9],["12",17,0.6]] },
    sparkle: { s: [P("M12 3l1.6 5L19 9.5l-5.4 1.5L12 16l-1.6-5L5 9.5l5.4-1.5zM18 15l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z")] },
    arrow_up: { s: [P("M12 19V5M6 11l6-6 6 6")] },
    pencil: { s: [P("M4 20l1-4L16 5l3 3L8 19zM14 7l3 3")] },
    xmark: { s: [P("M6 6l12 12M18 6L6 18")] },
    handbag_clock: { s: [P("M12 3v3M12 12l2 1")], c:[["12",12,9]] },
  };

  function Icon({ name, size = 20, stroke = 1.7, style = {}, fill = false }) {
    const g = G[name] || G.tag;
    return (
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none" style={{ display: 'block', flexShrink: 0, ...style }}>
        {(g.s || []).map((p, i) => p.d ? (
          <path key={'p' + i} d={p.d} stroke="currentColor" strokeWidth={stroke}
                strokeLinecap="round" strokeLinejoin="round" fill={fill ? 'currentColor' : 'none'} />
        ) : null)}
        {(g.c || []).map((c, i) => (
          <circle key={'c' + i} cx={c[0]} cy={c[1]} r={c[2]} stroke="currentColor" strokeWidth={stroke} fill="none" />
        ))}
      </svg>
    );
  }

  window.Icon = Icon;
  window.GG_ICON_FOR_CATEGORY = (cat) => ({
    Groceries: 'cart', Food: 'fork.knife', Transport: 'car', Coffee: 'cup.and.saucer',
    Bills: 'doc.text', Shopping: 'bag',
  }[cat] || 'tag');
})();
