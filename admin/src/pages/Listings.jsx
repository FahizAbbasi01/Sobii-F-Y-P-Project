import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api.js';
import { ActionModal, Badge, Loader, Pager, Tabs, fmtDate, pkr, useLoad } from '../components/ui.jsx';

export default function Listings() {
  const [status, setStatus] = useState('active');
  const [q, setQ] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [removing, setRemoving] = useState(null);
  const state = useLoad(() => api.get('/admin/listings', { status, q: search, page, limit: 25 }), [status, search, page]);

  return (
    <>
      <div className="page-head">
        <div><h1>Listings</h1><div className="muted">{state.data ? `${state.data.total} listing(s)` : ' '}</div></div>
        <form className="row" onSubmit={(e) => { e.preventDefault(); setSearch(q); setPage(1); }}>
          <input placeholder="Search title, brand, model" value={q} onChange={(e) => setQ(e.target.value)} />
          <button className="btn ghost">Search</button>
        </form>
      </div>
      <Tabs value={status} onChange={(v) => { setStatus(v); setPage(1); }} options={[['active', 'Active'], ['reserved', 'Reserved'], ['sold', 'Sold'], ['withdrawn', 'Withdrawn'], ['removed', 'Removed'], ['', 'All']]} />
      <div className="card table-wrap">
        <Loader state={state}>
          {(d) => d.listings.length === 0 ? <div className="empty">No listings.</div> : (
            <table>
              <thead><tr><th>Listing</th><th>Device</th><th>Seller</th><th>Price</th><th>Status</th><th /></tr></thead>
              <tbody>
                {d.listings.map((l) => (
                  <tr key={l.id}>
                    <td><b>{l.title}</b><div className="small muted">{l.city} • {l.condition.replace('_', ' ')} • {fmtDate(l.created_at)}</div></td>
                    <td><Link to={`/devices/${l.device_id}`}>{l.brand} {l.model}</Link><div><Badge value={l.registry_status} /></div></td>
                    <td>{l.seller_name}<div className="small muted">{l.seller_email}</div></td>
                    <td className="mono">{pkr(l.price)}</td>
                    <td><Badge value={l.status} /></td>
                    <td>{['active', 'reserved'].includes(l.status) && <button className="btn sm danger" onClick={() => setRemoving(l)}>Remove</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Loader>
        {state.data && <Pager page={page} setPage={setPage} count={state.data.listings.length} limit={25} />}
      </div>
      {removing && (
        <ActionModal
          title={`Remove "${removing.title}"?`}
          message="The listing is taken down, open requests are declined and any pending sale transfer is cancelled."
          confirmLabel="Remove listing"
          danger
          needNote="optional"
          notePlaceholder="Reason shown to the seller"
          onConfirm={(note) => api.post(`/admin/listings/${removing.id}/remove`, { note: note || null })}
          onClose={(done) => { setRemoving(null); if (done) state.reload(); }}
        />
      )}
    </>
  );
}
