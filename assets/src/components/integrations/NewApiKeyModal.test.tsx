import React from 'react';
import {render, screen} from '@testing-library/react';
import NewApiKeyModal from './NewApiKeyModal';

// Regression guard for the antd 5 Modal `visible` -> `open` migration: the
// modal content is shown when its `visible` prop is true.
describe('NewApiKeyModal', () => {
  it('renders modal content when visible', () => {
    render(
      <NewApiKeyModal visible onSuccess={() => {}} onCancel={() => {}} />
    );

    // Modal renders (in a portal) with API-key-related content when open.
    expect(screen.getAllByText(/api key/i).length).toBeGreaterThan(0);
  });
});
