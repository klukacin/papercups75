import React from 'react';
import {
  BrowserRouter as Router,
  Navigate,
  Route,
  Routes,
  useLocation,
} from 'react-router-dom';
import {useAuth} from './components/auth/AuthProvider';
import Login from './components/auth/Login';
import Register from './components/auth/Register';
import EmailVerification from './components/auth/EmailVerification';
import PasswordReset from './components/auth/PasswordReset';
import RequestPasswordReset from './components/auth/RequestPasswordReset';
import PasswordResetRequested from './components/auth/PasswordResetRequested';
import Demo from './components/demo/Demo';
import BotDemo from './components/demo/BotDemo';
import Dashboard from './components/Dashboard';
import Sandbox from './components/Sandbox';
import SharedConversation from './components/conversations/SharedConversation';
import './App.css';

const RedirectToLogin = () => {
  const location = useLocation();

  return <Navigate to={`/login?redirect=${location.pathname}`} replace />;
};

const App = () => {
  const auth = useAuth();

  if (auth.loading) {
    return null; // FIXME: show loading icon
  }

  if (!auth.isAuthenticated) {
    // Public routes
    return (
      <Router>
        <Routes>
          <Route path="/demo" element={<Demo />} />
          <Route path="/bot/demo" element={<BotDemo />} />
          <Route path="/login" element={<Login />} />
          <Route path="/register/:invite" element={<Register />} />
          <Route path="/register" element={<Register />} />
          <Route path="/verify" element={<EmailVerification />} />
          <Route path="/reset-password" element={<RequestPasswordReset />} />
          <Route path="/reset" element={<PasswordReset />} />
          <Route
            path="/reset-password-requested"
            element={<PasswordResetRequested />}
          />
          <Route path="/sandbox" element={<Sandbox />} />
          <Route path="/share" element={<SharedConversation />} />
          <Route path="*" element={<RedirectToLogin />} />
        </Routes>
      </Router>
    );
  }

  // Private routes
  return (
    <Router>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/register/:invite" element={<Register />} />
        <Route path="/register" element={<Register />} />
        <Route path="/verify" element={<EmailVerification />} />
        <Route path="/reset-password" element={<RequestPasswordReset />} />
        <Route path="/reset" element={<PasswordReset />} />
        <Route
          path="/reset-password-requested"
          element={<PasswordResetRequested />}
        />
        <Route path="/demo" element={<Demo />} />
        <Route path="/bot/demo" element={<BotDemo />} />
        <Route path="/sandbox" element={<Sandbox />} />
        <Route path="/share" element={<SharedConversation />} />
        <Route path="/*" element={<Dashboard />} />
      </Routes>
    </Router>
  );
};

export default App;
