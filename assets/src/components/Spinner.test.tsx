import React from 'react';
import {render} from '@testing-library/react';
import Spinner from './Spinner';

// Smoke test: also verifies that components importing from ./common (which pulls
// antd 5 + react-syntax-highlighter) render under jest after the upgrade.
describe('Spinner', () => {
  it('renders an antd spin indicator without crashing', () => {
    const {container} = render(<Spinner size={24} />);
    expect(container.querySelector('.ant-spin')).toBeInTheDocument();
  });
});
