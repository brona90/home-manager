---
description: Mobile/responsive requirements for frontend changes. Loaded only when editing frontend files so it doesn't consume context on every turn.
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.css"
  - "**/*.scss"
  - "**/*.html"
  - "**/*.vue"
  - "**/*.razor"
  - "**/*.cshtml"
---

# Mobile Support Checklist

**Every frontend change must consider both desktop and mobile.**

## Quick Mobile Checklist (for frontend changes)

**Before Implementation:**
- [ ] Review component guidelines
- [ ] Identify which breakpoints need custom styles (768px, 480px)

**During Implementation:**
- [ ] Desktop CSS unchanged (add mobile styles in a new section)
- [ ] Touch targets ≥44px for buttons/links
- [ ] Forms stack vertically on mobile
- [ ] Grids collapse to single column

**Testing:**
- [ ] Test at 768px width (mobile breakpoint)
- [ ] Test at 480px width (small mobile)
- [ ] Verify desktop unchanged at >1024px
- [ ] No horizontal scroll on mobile

## CSS Section Template

```css
/* ========== DESKTOP STYLES (DO NOT MODIFY) ========== */
.component { ... }

/* ========== MOBILE STYLES (≤768px) ========== */
@media (max-width: 768px) {
    .component { ... }
}
```

## Breakpoints Reference
- Desktop: >1024px (full experience)
- Tablet: 768px–1024px (simplified nav)
- Mobile: <768px (hamburger menu, stacked layouts)
- Small Mobile: <480px (further size reductions)
