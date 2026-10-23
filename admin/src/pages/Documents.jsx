import { useState } from 'react';
import { api } from '../api.js';
import { ActionModal, Badge, Loader, Pager, Tabs, fmtDate, useLoad } from '../components/ui.jsx';

export default function Documents() {
  const [status, setStatus] = useState('pending');
  const [page, setPage] = useState(1);
  const [action, setAction] = useState(null);
  const [error, setError] = useState(null);
  const state = useLoad(() => api.get('/admin/documents', { status, page, limit: 25 }), [status, page]);

  const view = async (doc) => {
    setError(null);
    // Open the window first (synchronously) so popup blockers allow it, then point it at the signed URL.
    const win = window.open('', '_blank');
    if (win) win.opener = null;
    try {
      const { url } = await api.get(`/admin/documents/${doc.id}/url`);
      if (win) win.location.href = url; else window.location.href = url;
    } catch (e) {
      win?.close();
      setError(e.message);
    }
  };

  return (
    <>
      <div className="page-head"><div><h1>Document review</h1><div className="muted">Receipts, box photos and police reports uploaded by users. Links expire after an hour and each view is audit-logged.</div></div></div>
      <Tabs value={status} onChange={(v) => { setStatus(v); setPage(1); }} options={[['pending', 'Pending'], ['approved', 'Approved'], ['rejected', 'Rejected'], ['', 'All']]} />
      {error && <div className="error">{error}</div>}
      <div className="card table-wrap">
        <Loader state={state}>
          {(d) => d.documents.length === 0 ? <div className="empty">No documents here.</div> : (
            <table>
              <thead><tr><th>Type</th><th>Owner</th><th>Device</th><th>File</th><th>Uploaded</th><th>Status</th><th /></tr></thead>
              <tbody>
                {d.documents.map((doc) => (
                  <tr key={doc.id}>
                    <td><b>{doc.kind.replace(/_/g, ' ')}</b>{doc.stolen_report_id && <div className="small muted">attached to stolen report</div>}</td>
                    <td>{doc.owner_name}<div className="small muted">{doc.owner_email}</div></td>
                    <td>{doc.brand ? `${doc.brand} ${doc.model}` : '—'}</td>
                    <td><button className="btn sm ghost" onClick={() => view(doc)}>View</button><div className="small muted">{doc.mime_type} • {(doc.size_bytes / 1024).toFixed(0)} KB</div></td>
                    <td className="small">{fmtDate(doc.created_at)}</td>
                    <td><Badge value={doc.status} />{doc.review_note && <div className="small muted">{doc.review_note}</div>}</td>
                    <td>
                      {doc.status === 'pending' && (
                        <div className="row">
                          <button className="btn sm" onClick={() => setAction({ doc, decision: 'approved' })}>Approve</button>
                          <button className="btn sm ghost" onClick={() => setAction({ doc, decision: 'rejected' })}>Reject</button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Loader>
        {state.data && <Pager page={page} setPage={setPage} count={state.data.documents.length} limit={25} />}
      </div>
      {action && (
        <ActionModal
          title={action.decision === 'approved' ? 'Approve document?' : 'Reject document?'}
          message="The owner will be notified."
          confirmLabel={action.decision === 'approved' ? 'Approve' : 'Reject'}
          danger={action.decision === 'rejected'}
          needNote="optional"
          onConfirm={(note) => api.post(`/admin/documents/${action.doc.id}/review`, { decision: action.decision, note: note || null })}
          onClose={(done) => { setAction(null); if (done) state.reload(); }}
        />
      )}
    </>
  );
}
