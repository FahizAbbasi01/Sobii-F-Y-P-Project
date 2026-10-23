import { useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { api } from '../api.js';
import { Badge, Loader, Pager, fmtDate, pkr, useLoad } from '../components/ui.jsx';

export default function Devices() {
  const [params, setParams] = useSearchParams();
  const search = params.get('q') || '';
  const [q, setQ] = useState(search);
  const [page, setPage] = useState(1);
  const state = useLoad(() => api.get('/admin/devices', { q: search, page, limit: 25 }), [search, page]);

  return (
    <>
      <div className="page-head">
        <div><h1>Devices & ownership history</h1><div className="muted">Search by IMEI (4+ digits), brand, model or owner email.</div></div>
        <form className="row" onSubmit={(e) => { e.preventDefault(); setParams(q ? { q } : {}); setPage(1); }}>
          <input placeholder="IMEI, model or email" value={q} onChange={(e) => setQ(e.target.value)} />
          <button className="btn ghost">Search</button>
        </form>
      </div>
      <div className="card table-wrap">
        <Loader state={state}>
          {(d) => d.devices.length === 0 ? <div className="empty">No devices match.</div> : (
            <table>
              <thead><tr><th>Device</th><th>IMEI(s)</th><th>Current owner</th><th>Registered</th><th>Status</th></tr></thead>
              <tbody>
                {d.devices.map((x) => (
                  <tr key={x.id}>
                    <td><Link to={`/devices/${x.id}`}><b>{x.brand} {x.model}</b></Link>{x.storage_gb && <div className="small muted">{x.storage_gb}GB</div>}</td>
                    <td className="mono small">{x.imeis}</td>
                    <td>{x.owner_name}<div className="small muted">{x.owner_email}</div></td>
                    <td className="small">{fmtDate(x.created_at)}</td>
                    <td><Badge value={x.registry_status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Loader>
        {state.data && <Pager page={page} setPage={setPage} count={state.data.devices.length} limit={25} />}
      </div>
    </>
  );
}

export function DeviceDetail() {
  const { id } = useParams();
  const state = useLoad(() => api.get(`/admin/devices/${id}`), [id]);
  return (
    <Loader state={state}>
      {(d) => (
        <>
          <div className="page-head">
            <div>
              <div className="small"><Link to="/devices">← Devices</Link></div>
              <h1>{d.device.brand} {d.device.model} <Badge value={d.device.registry_status} /></h1>
              <div className="mono muted">{(d.device.imeis || []).map((i) => `IMEI ${i.slot}: ${i.imei}`).join('   ')}</div>
            </div>
            <div className="card" style={{ padding: '10px 14px' }}>
              <div className="small muted">Current owner</div><b>{d.device.owner_name}</b><div className="small">{d.device.owner_email}</div>
            </div>
          </div>
          <div className="grid two">
            <div className="card">
              <h2>Ownership history</h2>
              <div className="timeline">
                {d.ownershipHistory.map((h) => (
                  <div key={h.id} className={h.released_at ? '' : 'current'}>
                    <b>{h.full_name}</b> <span className="small muted">{h.email}</span>
                    <div className="small">{h.acquired_via.replace('_', ' ')} • {fmtDate(h.acquired_at)} → {h.released_at ? fmtDate(h.released_at) : 'present'}</div>
                  </div>
                ))}
              </div>
              <h2 style={{ marginTop: 16 }}>Transfers</h2>
              {d.transfers.length === 0 ? <div className="muted">None</div> : (
                <table><tbody>
                  {d.transfers.map((t) => (
                    <tr key={t.id}><td>{t.from_name} → {t.to_name}<div className="small muted">{fmtDate(t.created_at)}{t.purchase_request_id ? ' • marketplace sale' : ' • direct'}</div></td><td><Badge value={t.status} /></td></tr>
                  ))}
                </tbody></table>
              )}
            </div>
            <div className="grid" style={{ alignContent: 'start' }}>
              <div className="card">
                <h2>Stolen reports</h2>
                {d.reports.length === 0 ? <div className="muted">None</div> : d.reports.map((r) => (
                  <div key={r.id} style={{ marginBottom: 10 }}><Badge value={r.status} /> {r.reporter_name} • {fmtDate(r.created_at)}<div className="small muted">{r.location}: {r.description}</div></div>
                ))}
              </div>
              <div className="card">
                <h2>Listings</h2>
                {d.listings.length === 0 ? <div className="muted">None</div> : d.listings.map((l) => (
                  <div key={l.id} className="row" style={{ justifyContent: 'space-between', marginBottom: 6 }}><span>{l.title}</span><span className="mono small">{pkr(l.price)}</span><Badge value={l.status} /></div>
                ))}
              </div>
            </div>
          </div>
          <div className="card" style={{ marginTop: 16 }}>
            <h2>Audit trail</h2>
            <div className="table-wrap"><table>
              <thead><tr><th>When</th><th>Actor</th><th>Action</th><th>Details</th></tr></thead>
              <tbody>
                {d.audit.map((a) => (
                  <tr key={a.id}><td className="small">{fmtDate(a.created_at)}</td><td>{a.actor_name || 'system'}</td><td className="mono small">{a.action}</td><td className="mono small" style={{ maxWidth: 420, wordBreak: 'break-all' }}>{JSON.stringify(a.metadata)}</td></tr>
                ))}
              </tbody>
            </table></div>
          </div>
        </>
      )}
    </Loader>
  );
}
