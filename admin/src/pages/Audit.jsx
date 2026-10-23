import { useState } from 'react';
import { api } from '../api.js';
import { Loader, Pager, fmtDate, useLoad } from '../components/ui.jsx';

export default function Audit() {
  const [action, setAction] = useState('');
  const [filter, setFilter] = useState('');
  const [page, setPage] = useState(1);
  const state = useLoad(() => api.get('/admin/audit', { action: filter, page, limit: 50 }), [filter, page]);
  return (
    <>
      <div className="page-head">
        <div><h1>Audit log</h1><div className="muted">Append-only. The database rejects edits and deletes.</div></div>
        <form className="row" onSubmit={(e) => { e.preventDefault(); setFilter(action); setPage(1); }}>
          <select value={action} onChange={(e) => setAction(e.target.value)}>
            <option value="">All actions</option>
            {['user.', 'device.', 'listing.', 'purchase.', 'transfer.', 'report.', 'document.', 'admin.'].map((p) => <option key={p} value={p}>{p}*</option>)}
          </select>
          <button className="btn ghost">Filter</button>
        </form>
      </div>
      <div className="card table-wrap">
        <Loader state={state}>
          {(d) => (
            <table>
              <thead><tr><th>When</th><th>Actor</th><th>Action</th><th>Entity</th><th>Details</th><th>IP</th></tr></thead>
              <tbody>
                {d.entries.map((a) => (
                  <tr key={a.id}>
                    <td className="small">{fmtDate(a.created_at)}</td>
                    <td>{a.actor_name || 'system'}<div className="small muted">{a.actor_email}</div></td>
                    <td className="mono small">{a.action}</td>
                    <td className="mono small">{a.entity_type}<div className="muted">{a.entity_id?.slice(0, 8)}</div></td>
                    <td className="mono small" style={{ maxWidth: 360, wordBreak: 'break-all' }}>{JSON.stringify(a.metadata)}</td>
                    <td className="mono small">{a.ip || ''}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Loader>
        {state.data && <Pager page={page} setPage={setPage} count={state.data.entries.length} limit={50} />}
      </div>
    </>
  );
}
