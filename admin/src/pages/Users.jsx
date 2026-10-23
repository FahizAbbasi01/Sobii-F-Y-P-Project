import { useState } from 'react';
import { api } from '../api.js';
import { ActionModal, Badge, Loader, Pager, Tabs, fmtDay, useLoad } from '../components/ui.jsx';

export default function Users() {
  const [status, setStatus] = useState('');
  const [q, setQ] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [target, setTarget] = useState(null);
  const state = useLoad(() => api.get('/admin/users', { status, q: search, page, limit: 25 }), [status, search, page]);

  return (
    <>
      <div className="page-head">
        <div><h1>Users</h1><div className="muted">{state.data ? `${state.data.total} user(s)` : ' '}</div></div>
        <form className="row" onSubmit={(e) => { e.preventDefault(); setSearch(q); setPage(1); }}>
          <input placeholder="Search name or email" value={q} onChange={(e) => setQ(e.target.value)} />
          <button className="btn ghost">Search</button>
        </form>
      </div>
      <Tabs value={status} onChange={(v) => { setStatus(v); setPage(1); }} options={[['', 'All'], ['active', 'Active'], ['suspended', 'Suspended']]} />
      <div className="card table-wrap">
        <Loader state={state}>
          {(d) => d.users.length === 0 ? <div className="empty">No users found.</div> : (
            <table>
              <thead><tr><th>User</th><th>Contact</th><th>Devices</th><th>Listings</th><th>Joined</th><th>Status</th><th /></tr></thead>
              <tbody>
                {d.users.map((u) => (
                  <tr key={u.id}>
                    <td><b>{u.full_name}</b> {u.role === 'admin' && <Badge value="admin" />}<div className="small muted">{u.city || '—'}</div></td>
                    <td>{u.email}<div className="small muted">{u.phone || ''}</div></td>
                    <td>{u.devices}</td>
                    <td>{u.listings}</td>
                    <td className="small">{fmtDay(u.created_at)}</td>
                    <td><Badge value={u.status} /></td>
                    <td>
                      {u.role !== 'admin' && (u.status === 'active'
                        ? <button className="btn sm danger" onClick={() => setTarget({ u, status: 'suspended' })}>Suspend</button>
                        : <button className="btn sm ghost" onClick={() => setTarget({ u, status: 'active' })}>Reactivate</button>)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Loader>
        {state.data && <Pager page={page} setPage={setPage} count={state.data.users.length} limit={25} />}
      </div>
      {target && (
        <ActionModal
          title={target.status === 'suspended' ? `Suspend ${target.u.full_name}?` : `Reactivate ${target.u.full_name}?`}
          message={target.status === 'suspended' ? 'They are signed out everywhere and blocked from the app immediately.' : 'They can sign in again.'}
          confirmLabel={target.status === 'suspended' ? 'Suspend' : 'Reactivate'}
          danger={target.status === 'suspended'}
          needNote="optional"
          notePlaceholder="Internal note (audit log)"
          onConfirm={(note) => api.post(`/admin/users/${target.u.id}/status`, { status: target.status, ...(note ? { note } : {}) })}
          onClose={(done) => { setTarget(null); if (done) state.reload(); }}
        />
      )}
    </>
  );
}
