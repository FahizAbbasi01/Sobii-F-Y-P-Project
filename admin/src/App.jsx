import { useEffect, useState } from 'react';
import { Navigate, NavLink, Route, Routes, useNavigate } from 'react-router-dom';
import { api, hasSession, login, logout, me, setOnExpired } from './api.js';
import Dashboard from './pages/Dashboard.jsx';
import Users from './pages/Users.jsx';
import Listings from './pages/Listings.jsx';
import Reports from './pages/Reports.jsx';
import Documents from './pages/Documents.jsx';
import Disputes from './pages/Disputes.jsx';
import Devices, { DeviceDetail } from './pages/Devices.jsx';
import Audit from './pages/Audit.jsx';

function Login({ onLogin }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setError(null);
    try { onLogin(await login(email.trim(), password)); } catch (err) { setError(err.message); setBusy(false); }
  };
  return (
    <div className="login">
      <form className="card" onSubmit={submit}>
        <div className="brand" style={{ padding: 0, marginBottom: 18, color: 'var(--ink)' }}>
          <div className="brand-mark" style={{ color: '#fff' }}>✓</div> DeviceTrust Admin
        </div>
        <h1>Sign in</h1>
        <p className="muted small" style={{ marginTop: 0 }}>Admin accounts only. Created with <span className="mono">npm run seed:admin</span>.</p>
        {error && <div className="error">{error}</div>}
        <div style={{ marginBottom: 12 }}><label>Email</label><input style={{ width: '100%' }} type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus /></div>
        <div style={{ marginBottom: 18 }}><label>Password</label><input style={{ width: '100%' }} type="password" value={password} onChange={(e) => setPassword(e.target.value)} required /></div>
        <button className="btn navy" style={{ width: '100%' }} disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
      </form>
    </div>
  );
}

function Shell({ user, onLogout }) {
  const [counts, setCounts] = useState({});
  useEffect(() => {
    api.get('/admin/stats').then((s) => setCounts(s.totals)).catch(() => {});
  }, []);
  const links = [
    ['/', 'Dashboard'],
    ['/reports', 'Stolen reports', counts.pending_reports],
    ['/documents', 'Documents', counts.pending_documents],
    ['/disputes', 'Disputes', counts.open_disputes],
    ['/listings', 'Listings'],
    ['/users', 'Users'],
    ['/devices', 'Devices & history'],
    ['/audit', 'Audit log'],
  ];
  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="brand"><div className="brand-mark">✓</div> DeviceTrust</div>
        <nav className="nav">
          {links.map(([to, label, n]) => (
            <NavLink key={to} to={to} end={to === '/'}>{label}{n ? <span className="count">{n}</span> : null}</NavLink>
          ))}
        </nav>
        <div className="sidebar-foot">
          <div style={{ color: '#fff' }}>{user.fullName}</div>
          <div>{user.email}</div>
          <button className="btn sm ghost" style={{ marginTop: 8 }} onClick={onLogout}>Sign out</button>
        </div>
      </aside>
      <main className="main">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/reports" element={<Reports />} />
          <Route path="/documents" element={<Documents />} />
          <Route path="/disputes" element={<Disputes />} />
          <Route path="/listings" element={<Listings />} />
          <Route path="/users" element={<Users />} />
          <Route path="/devices" element={<Devices />} />
          <Route path="/devices/:id" element={<DeviceDetail />} />
          <Route path="/audit" element={<Audit />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}

export default function App() {
  const [user, setUser] = useState(null);
  const [checking, setChecking] = useState(hasSession());
  const navigate = useNavigate();

  useEffect(() => {
    setOnExpired(() => { setUser(null); navigate('/'); });
    if (hasSession()) me().then(setUser).catch(() => {}).finally(() => setChecking(false));
  }, [navigate]);

  if (checking) return <div className="empty">Loading…</div>;
  if (!user) return <Login onLogin={setUser} />;
  return <Shell user={user} onLogout={async () => { await logout(); setUser(null); }} />;
}
