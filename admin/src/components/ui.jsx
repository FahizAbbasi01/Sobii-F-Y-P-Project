import { useCallback, useEffect, useState } from 'react';

const KIND = {
  registered: 'success', active: 'success', approved: 'success', completed: 'success', resolved: 'success',
  pending: 'warning', reserved: 'warning', open: 'warning', disputed: 'danger',
  reported_stolen: 'danger', rejected: 'danger', removed: 'danger', suspended: 'danger',
  sold: 'info', admin: 'info', accepted: 'info',
};

export function Badge({ value }) {
  if (!value) return null;
  return <span className={`badge ${KIND[value] || ''}`}>{String(value).replace(/_/g, ' ')}</span>;
}

export const fmtDate = (s) => (s ? new Date(s).toLocaleString('en-PK', { dateStyle: 'medium', timeStyle: 'short' }) : '—');
export const fmtDay = (s) => (s ? new Date(s).toLocaleDateString('en-PK', { dateStyle: 'medium' }) : '—');
export const pkr = (n) => (n == null ? '—' : `PKR ${Number(n).toLocaleString('en-US')}`);

/** Loads data from an async function; returns { data, error, loading, reload }. */
export function useLoad(fn, deps = []) {
  const [state, setState] = useState({ data: null, error: null, loading: true });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const load = useCallback(fn, deps);
  const reload = useCallback(() => {
    setState((s) => ({ ...s, loading: true, error: null }));
    load().then((data) => setState({ data, error: null, loading: false }), (error) => setState({ data: null, error, loading: false }));
  }, [load]);
  useEffect(() => { reload(); }, [reload]);
  return { ...state, reload };
}

export function Loader({ state, children }) {
  if (state.loading && !state.data) return <div className="empty">Loading…</div>;
  if (state.error) return <div className="error">{state.error.message} <button className="btn sm ghost" onClick={state.reload}>Retry</button></div>;
  return children(state.data);
}

export function Tabs({ value, options, onChange }) {
  return (
    <div className="tabs">
      {options.map(([v, label]) => (
        <button key={v || 'all'} className={value === v ? 'on' : ''} onClick={() => onChange(v)}>{label}</button>
      ))}
    </div>
  );
}

/** Confirmation modal with an optional note field. */
export function ActionModal({ title, message, confirmLabel = 'Confirm', danger, needNote, notePlaceholder, onConfirm, onClose }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const submit = async () => {
    if (needNote === 'required' && note.trim().length < 5) { setError('Please write at least 5 characters.'); return; }
    setBusy(true); setError(null);
    try { await onConfirm(note.trim()); onClose(true); } catch (e) { setError(e.message); setBusy(false); }
  };
  return (
    <div className="modal-back" onClick={() => !busy && onClose(false)}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>{title}</h2>
        <p className="muted">{message}</p>
        {needNote && (
          <div style={{ marginBottom: 14 }}>
            <label>{needNote === 'required' ? 'Reason (required)' : 'Note (optional, shown to the user)'}</label>
            <textarea value={note} onChange={(e) => setNote(e.target.value)} placeholder={notePlaceholder} />
          </div>
        )}
        {error && <div className="error">{error}</div>}
        <div className="row" style={{ justifyContent: 'flex-end' }}>
          <button className="btn ghost" disabled={busy} onClick={() => onClose(false)}>Cancel</button>
          <button className={`btn ${danger ? 'danger' : 'navy'}`} disabled={busy} onClick={submit}>{busy ? 'Working…' : confirmLabel}</button>
        </div>
      </div>
    </div>
  );
}

export function Pager({ page, setPage, count, limit }) {
  return (
    <div className="row" style={{ justifyContent: 'flex-end', marginTop: 12 }}>
      <button className="btn sm ghost" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
      <span className="small muted">Page {page}</span>
      <button className="btn sm ghost" disabled={count < limit} onClick={() => setPage(page + 1)}>Next</button>
    </div>
  );
}
