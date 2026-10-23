import { useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api.js';
import { ActionModal, Badge, Loader, Tabs, fmtDate, useLoad } from '../components/ui.jsx';

export default function Disputes() {
  const [status, setStatus] = useState('open');
  const [action, setAction] = useState(null);
  const state = useLoad(() => api.get('/admin/disputes', { status, limit: 50 }), [status]);

  return (
    <>
      <div className="page-head"><div><h1>Disputes</h1><div className="muted">A dispute freezes its transfer until you resolve it.</div></div></div>
      <Tabs value={status} onChange={setStatus} options={[['open', 'Open'], ['resolved', 'Transfer cancelled'], ['rejected', 'Dismissed'], ['', 'All']]} />
      <div className="card table-wrap">
        <Loader state={state}>
          {(d) => d.disputes.length === 0 ? <div className="empty">No disputes here.</div> : (
            <table>
              <thead><tr><th>Device</th><th>Transfer</th><th>Raised by</th><th>Reason</th><th>Status</th><th /></tr></thead>
              <tbody>
                {d.disputes.map((x) => (
                  <tr key={x.id}>
                    <td><Link to={`/devices/${x.device_id}`}><b>{x.brand} {x.model}</b></Link></td>
                    <td>{x.from_name} → {x.to_name}<div><Badge value={x.transfer_status} /></div></td>
                    <td>{x.raised_by_name}<div className="small muted">{x.raised_by_email}</div><div className="small muted">{fmtDate(x.created_at)}</div></td>
                    <td style={{ maxWidth: 320 }}>{x.reason}{x.resolution && <div className="small muted" style={{ marginTop: 6 }}>Resolution: {x.resolution}</div>}</td>
                    <td><Badge value={x.status} /></td>
                    <td>
                      {x.status === 'open' && (
                        <div className="row">
                          <button className="btn sm danger" onClick={() => setAction({ x, kind: 'cancel_transfer' })}>Cancel transfer</button>
                          <button className="btn sm ghost" onClick={() => setAction({ x, kind: 'resume_transfer' })}>Dismiss</button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Loader>
      </div>
      {action && (
        <ActionModal
          title={action.kind === 'cancel_transfer' ? 'Cancel this transfer?' : 'Dismiss dispute?'}
          message={action.kind === 'cancel_transfer'
            ? 'Ownership stays with the current owner and any reserved listing re-opens.'
            : 'The transfer returns to pending; both parties must still confirm before ownership changes.'}
          confirmLabel={action.kind === 'cancel_transfer' ? 'Cancel transfer' : 'Dismiss dispute'}
          danger={action.kind === 'cancel_transfer'}
          needNote="required"
          notePlaceholder="Resolution shown to both parties"
          onConfirm={(note) => api.post(`/admin/disputes/${action.x.id}/resolve`, { action: action.kind, resolution: note })}
          onClose={(done) => { setAction(null); if (done) state.reload(); }}
        />
      )}
    </>
  );
}
