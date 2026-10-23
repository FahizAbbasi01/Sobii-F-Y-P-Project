import { Link } from 'react-router-dom';
import { api } from '../api.js';
import { Loader, fmtDate, useLoad } from '../components/ui.jsx';

const CARDS = [
  ['users', 'Users'], ['new_users_7d', 'New users (7d)'], ['devices', 'Registered devices'],
  ['stolen_devices', 'Flagged stolen', 'alert'], ['active_listings', 'Active listings'], ['sold_listings', 'Sold listings'],
  ['completed_transfers', 'Completed transfers'], ['pending_transfers', 'Pending transfers', 'warn'],
  ['pending_reports', 'Reports to review', 'warn'], ['pending_documents', 'Documents to review', 'warn'],
  ['open_disputes', 'Open disputes', 'alert'], ['lookups_24h', 'IMEI lookups (24h)'],
];

const FLAG_LINK = (f) => {
  if (f.ref.deviceId) return `/devices/${f.ref.deviceId}`;
  if (f.ref.imei) return `/devices?q=${f.ref.imei}`;
  if (f.ref.userId) return '/users';
  if (f.ref.listingId) return '/listings';
  return null;
};

function Chart({ daily }) {
  const max = Math.max(1, ...daily.map((d) => Math.max(d.registrations, d.transfers)));
  return (
    <>
      <div className="bars">
        {daily.map((d) => (
          <div className="col" key={d.day} title={`${d.day}: ${d.registrations} registrations, ${d.transfers} transfers`}>
            <div style={{ display: 'flex', gap: 2, alignItems: 'flex-end', height: 128 }}>
              <div className="b1" style={{ flex: 1, height: Math.round((d.registrations / max) * 128), minHeight: d.registrations ? 3 : 0 }} />
              <div className="b2" style={{ flex: 1, height: Math.round((d.transfers / max) * 128), minHeight: d.transfers ? 3 : 0 }} />
            </div>
          </div>
        ))}
      </div>
      <div className="row small muted" style={{ justifyContent: 'space-between', marginTop: 4 }}>
        <span>{daily[0]?.day}</span><span>{daily[daily.length - 1]?.day}</span>
      </div>
      <div className="legend"><span><i style={{ background: 'var(--blue)' }} />Device registrations</span><span><i style={{ background: '#10b981' }} />Completed transfers</span></div>
    </>
  );
}

export default function Dashboard() {
  const stats = useLoad(() => api.get('/admin/stats'));
  const flags = useLoad(() => api.get('/admin/flags'));
  return (
    <>
      <div className="page-head">
        <div><h1>Overview</h1><div className="muted">Live figures from the DeviceTrust database.</div></div>
        <button className="btn ghost" onClick={() => { stats.reload(); flags.reload(); }}>Refresh</button>
      </div>
      <Loader state={stats}>
        {(s) => (
          <>
            <div className="grid stats" style={{ marginBottom: 16 }}>
              {CARDS.map(([k, label, tone]) => (
                <div key={k} className={`card stat ${s.totals[k] > 0 ? tone || '' : ''}`}>
                  <div className="value">{s.totals[k]}</div><div className="label">{label}</div>
                </div>
              ))}
            </div>
            <div className="grid two">
              <div className="card"><h2>Last 14 days</h2><Chart daily={s.daily} /></div>
              <div className="card">
                <h2>Suspicious activity</h2>
                <p className="small muted" style={{ marginTop: -6 }}>Rule-based hints for review, not verdicts.</p>
                <Loader state={flags}>
                  {(f) => (f.flags.length === 0 ? <div className="empty">No flags right now.</div> : f.flags.map((x, i) => {
                    const to = FLAG_LINK(x);
                    return (
                      <div className="flag" key={i}>
                        <span className={`dot ${x.severity}`} />
                        <div>
                          <div>{to ? <Link to={to}>{x.message}</Link> : x.message}</div>
                          <div className="small muted">{x.type.replace(/_/g, ' ')}{x.at ? ` • ${fmtDate(x.at)}` : ''}</div>
                        </div>
                      </div>
                    );
                  }))}
                </Loader>
              </div>
            </div>
          </>
        )}
      </Loader>
    </>
  );
}
