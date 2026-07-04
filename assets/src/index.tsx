import React from 'react';
import {createRoot} from 'react-dom/client';
import {ConfigProvider} from 'antd';
import './index.css';
import App from './App';
import analytics from './analytics';
import {AuthProvider} from './components/auth/AuthProvider';
import {accessibleTheme} from './theme';

analytics.init();

const root = createRoot(document.getElementById('root') as HTMLElement);
root.render(
  <ConfigProvider theme={accessibleTheme}>
    <AuthProvider>
      <App />
    </AuthProvider>
  </ConfigProvider>
);
