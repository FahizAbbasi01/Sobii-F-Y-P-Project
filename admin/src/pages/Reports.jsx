import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api.js';
import { ActionModal, Badge, Loader, Pager, Tabs, fmtDate, fmtDay, useLoad } from '../components/ui.jsx';

export default function Reports() {
  const [status, setStatus] = useState('pending');
  const [page, setPage] = useState(1);
  const [action, setAction] = useState(null);
  const state = useLoad(() => api.get('/admin/reports', { status, page, limit: 25 }), [status, page]);

  return (
    <>
      <div className="page-head"><div><h1>Stolen-device reports</h1><div className="muted">Approving flags the IMEI as stolen, removes listings and cancels transfers.</div></div></div>
      <Tabs value={status} onChange={(v) => { setStatus(v); setPage(1); }} options={[['pending', 'Pending'], ['approved', 'Approved'], ['rejected', 'Rejected'], ['', 'All']]} />
      <div className="card table-wrap">
        <Loader state={state}>
          {(d) => d.reports.length === 0 ? <div className="empty">No reports here.</div> : (
            <table>
              <thead><tr><th>Device</th><th>Reporter</th><th>Incident</th><th>Evidence</th><th>Status</th><th /></tr></thead>
              <tbody>
                {d.reports.map((r) => (
                  <tr key={r.id}>
                    <td><Link to={`/devices/${r.device_id}`}><b>{r.brand} {r.model}</b></Link><div className="mono small">{r.imeis}</div></td>
                    <td>{r.reporter_name}<div className="small muted">{r.reporter_email}</div></td>
                    <td style={{ maxWidth: 320 }}>
                      <div>{fmtDay(r.incident_date)} • {r.location}</div>
                      <div className="small muted">{r.description}</div>
                      {r.police_report_number && <div className="small">FIR: <span className="mono">{r.police_report_number}</span></div>}
                      <div className="small muted">Filed {fmtDate(r.created_at)}</div>
                    </td>
                    <td>{r.document_count > 0 ? <Link to="/documents">{r.document_count} file(s)</Link> : <span className="muted">None</span>}</td>
                    <td><Badge value={r.status} />{r.review_note && <div className="small muted" style={{ marginTop: 4 }}>{r.review_note}</div>}</td>
                    <td>
                      {r.status === 'pending' && (
                        <div className="row">
                          <button className="btn sm danger" onClick={() => setAction({ r, kind: 'approve' })}>Approve</button>
                          <button className="btn sm ghost" onClick={() => setAction({ r, kind: 'reject' })}>Reject</button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Loader>
        {state.data && <Pager page={page} setPage={setPage} count={state.data.reports.length} limit={25} />}
      </div>
      {action && (
        <ActionModal
          title={action.kind === 'approve' ? `Flag ${action.r.brand} ${action.r.model} as stolen?` : 'Reject this report?'}
          message={action.kind === 'approve'
            ? 'Public IMEI checks will show "Reported Stolen". Live listings are removed and pending transfers cancelled.'
            : 'The device stays "Registered". The reporter is notified.'}
          confirmLabel={action.kind === 'approve' ? 'Approve & flag' : 'Reject'}
          danger={action.kind === 'approve'}
          needNote="optional"
          notePlaceholder={action.kind === 'approve' ? 'e.g. FIR verified with police station' : 'e.g. No evidence provided'}
          onConfirm={(note) => api.post(`/admin/reports/${action.r.id}/${action.kind}`, { note: note || null })}
          onClose={(done) => { setAction(null); if (done) state.reload(); }}
        />
      )}
    </>
  );
}
