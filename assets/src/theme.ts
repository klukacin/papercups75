import type {ThemeConfig} from 'antd';

// WCAG 2.2 AA-oriented Ant Design theme overrides.
//
// antd 5's default tokens leave a few text colors below the 4.5:1 contrast
// ratio that WCAG 2.2 success criterion 1.4.3 (Contrast Minimum) requires for
// normal-size text on a white background:
//   - colorTextDescription / colorTextSecondary default to lighter grays
//   - colorTextPlaceholder defaults to ~rgba(0,0,0,0.25) (~1.6:1 — fails AA)
//
// We darken those so secondary, description and placeholder text clear 4.5:1.
// Disabled-control text is intentionally left at antd's default: WCAG exempts
// inactive UI components from the contrast requirement.
export const accessibleTheme: ThemeConfig = {
  token: {
    // ~5.7:1 on white
    colorTextSecondary: 'rgba(0, 0, 0, 0.65)',
    // ~4.7:1 on white
    colorTextDescription: 'rgba(0, 0, 0, 0.55)',
    // placeholder text raised from ~1.6:1 to ~4.7:1
    colorTextPlaceholder: 'rgba(0, 0, 0, 0.55)',
  },
};
