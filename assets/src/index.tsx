import React from 'react';
import {createRoot} from 'react-dom/client';
import {ConfigProvider} from 'antd';
import './index.css';
import App from './App';
import analytics from './analytics';
import {AuthProvider} from './components/auth/AuthProvider';
import {accessibleTheme} from './theme';
import * as serviceWorker from './serviceWorker';

analytics.init();

const root = createRoot(document.getElementById('root') as HTMLElement);
root.render(
  <ConfigProvider theme={accessibleTheme}>
    <AuthProvider>
      <App />
    </AuthProvider>
  </ConfigProvider>
);

// If you want your app to work offline and load faster, you can change
// unregister() to register() below. Note this comes with some pitfalls.
// Learn more about service workers: https://bit.ly/CRA-PWA
serviceWorker.unregister();
