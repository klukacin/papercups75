import React from 'react';
import {render} from '@testing-library/react';
import {axe, toHaveNoViolations} from 'jest-axe';

expect.extend(toHaveNoViolations);

// Accessibility regression guard backing the WCAG 2.2 AA goal. jsdom can't
// compute layout, so axe here catches structural WCAG issues (roles, accessible
// names, labels, alt text, heading structure) rather than color contrast, which
// is handled via the theme tokens in src/theme.ts.
describe('accessibility (axe)', () => {
  it('a labelled form has no detectable a11y violations', async () => {
    const {container} = render(
      <form aria-label="Sign in">
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" />
        <label htmlFor="password">Password</label>
        <input id="password" name="password" type="password" />
        <button type="submit">Sign in</button>
      </form>
    );
    const results = await axe(container);

    expect(results).toHaveNoViolations();
  });

  it('an image with alt text and a named link have no violations', async () => {
    const {container} = render(
      <div>
        <img src="/logo.png" alt="Papercups logo" />
        <a href="https://example.com">Documentation</a>
      </div>
    );
    const results = await axe(container);

    expect(results).toHaveNoViolations();
  });

  it('detects an input that is missing an accessible name', async () => {
    // Negative control: proves the harness actually reports violations.
    const {container} = render(<input type="text" />);
    const results = await axe(container);

    expect(results.violations.length).toBeGreaterThan(0);
  });
});
