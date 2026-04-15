import { useState, useEffect, useCallback } from 'react'
import './App.css'

interface OrderMetrics {
  storeId: string
  totalOrders: number
  totalRevenue: number
  avgOrderValue: number
}

interface WorkOrder {
  orderId: string
  customerId: string
  customerName: string
  orderTotal: number
  status: 'queued' | 'processing' | 'completed'
  queuedAt: string
}

interface QueueSummary {
  totalQueued: number
  totalProcessing: number
  orders: WorkOrder[]
}

const api = {
  placeOrder: (body: unknown) =>
    fetch('/api/orders', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }),
  getMetrics: (): Promise<OrderMetrics[]> =>
    fetch('/api/accounting/metrics').then(r => r.json()),
  getQueue: (): Promise<QueueSummary> =>
    fetch('/api/makeline/orders').then(r => r.json()),
  completeOrder: (orderId: string) =>
    fetch(`/api/makeline/orders/${orderId}/complete`, { method: 'PUT' }),
}

function MetricsCard({ metrics }: { metrics: OrderMetrics[] }) {
  const totals = metrics.reduce(
    (acc, m) => ({ orders: acc.orders + m.totalOrders, revenue: acc.revenue + m.totalRevenue }),
    { orders: 0, revenue: 0 }
  )
  return (
    <div className="card metrics-card">
      <h2>📊 Sales Metrics</h2>
      <div className="metrics-grid">
        <div className="metric">
          <span className="metric-value">{totals.orders.toLocaleString()}</span>
          <span className="metric-label">Total Orders</span>
        </div>
        <div className="metric">
          <span className="metric-value">${totals.revenue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
          <span className="metric-label">Total Revenue</span>
        </div>
      </div>
      {metrics.length > 0 && (
        <table className="metrics-table">
          <thead><tr><th>Store</th><th>Orders</th><th>Revenue</th><th>Avg</th></tr></thead>
          <tbody>
            {metrics.map(m => (
              <tr key={m.storeId}>
                <td>{m.storeId}</td><td>{m.totalOrders}</td>
                <td>${m.totalRevenue.toFixed(2)}</td><td>${m.avgOrderValue.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}

function MakelineQueue({ queue, onComplete }: { queue: QueueSummary, onComplete: (id: string) => void }) {
  return (
    <div className="card makeline-card">
      <h2>🍔 Makeline Queue</h2>
      <div className="queue-stats">
        <span className="badge">Queued: {queue.totalQueued}</span>
        <span className="badge processing">Processing: {queue.totalProcessing}</span>
      </div>
      <div className="queue-list">
        {(!queue.orders || queue.orders.length === 0) && <p className="empty">No pending orders 🎉</p>}
        {queue.orders?.filter(o => o.status !== 'completed').map(order => (
          <div key={order.orderId} className={`queue-item ${order.status}`}>
            <div className="order-info">
              <strong>{order.customerName}</strong>
              <span className="order-id">#{order.orderId.slice(0, 8)}</span>
            </div>
            <div className="order-meta">
              <span>${order.orderTotal?.toFixed(2)}</span>
              <span className={`status-badge ${order.status}`}>{order.status}</span>
            </div>
            {order.status === 'queued' && (
              <button className="complete-btn" onClick={() => onComplete(order.orderId)}>✅ Complete</button>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}

function PlaceOrderForm({ onOrderPlaced }: { onOrderPlaced: () => void }) {
  const [form, setForm] = useState({
    customerName: '', loyaltyId: '', productName: 'Red Dog Burger', quantity: 1, unitPrice: 9.99,
  })
  const [status, setStatus] = useState<'idle' | 'sending' | 'success' | 'error'>('idle')

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setStatus('sending')
    try {
      const res = await api.placeOrder({
        customerId: `cust-${Date.now()}`,
        customerName: form.customerName,
        loyaltyId: form.loyaltyId || undefined,
        items: [{ productId: 'p-001', productName: form.productName, quantity: form.quantity, unitPrice: form.unitPrice }],
      })
      if (!res.ok) throw new Error(await res.text())
      setStatus('success')
      setTimeout(() => { setStatus('idle'); onOrderPlaced() }, 1500)
    } catch { setStatus('error'); setTimeout(() => setStatus('idle'), 3000) }
  }

  return (
    <div className="card order-form-card">
      <h2>🛒 Place an Order</h2>
      <form onSubmit={submit}>
        <label>Customer Name<input required value={form.customerName} onChange={e => setForm(f => ({ ...f, customerName: e.target.value }))} placeholder="Jane Smith" /></label>
        <label>Loyalty ID<input value={form.loyaltyId} onChange={e => setForm(f => ({ ...f, loyaltyId: e.target.value }))} placeholder="optional" /></label>
        <label>Product<input required value={form.productName} onChange={e => setForm(f => ({ ...f, productName: e.target.value }))} /></label>
        <div className="form-row">
          <label>Qty<input type="number" min={1} value={form.quantity} onChange={e => setForm(f => ({ ...f, quantity: +e.target.value }))} /></label>
          <label>Price ($)<input type="number" step="0.01" min="0.01" value={form.unitPrice} onChange={e => setForm(f => ({ ...f, unitPrice: +e.target.value }))} /></label>
        </div>
        <button type="submit" disabled={status === 'sending'} className="submit-btn">
          {status === 'sending' ? '⏳ Placing…' : status === 'success' ? '✅ Placed!' : status === 'error' ? '❌ Error' : '🚀 Place Order'}
        </button>
      </form>
    </div>
  )
}

function App() {
  const [metrics, setMetrics] = useState<OrderMetrics[]>([])
  const [queue, setQueue] = useState<QueueSummary>({ totalQueued: 0, totalProcessing: 0, orders: [] })
  const [lastRefresh, setLastRefresh] = useState(new Date())

  const refresh = useCallback(async () => {
    try {
      const [m, q] = await Promise.all([api.getMetrics(), api.getQueue()])
      setMetrics(m); setQueue(q); setLastRefresh(new Date())
    } catch (err) { console.error('Refresh failed:', err) }
  }, [])

  useEffect(() => { refresh(); const t = setInterval(refresh, 10000); return () => clearInterval(t) }, [refresh])

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-content">
          <h1>🐕 Red Dog Order Management</h1>
          <div className="header-meta">
            <span className="tech-badge">Dapr</span>
            <span className="tech-badge">ACA</span>
            <span className="tech-badge">KEDA</span>
            <span className="refresh-time">Updated: {lastRefresh.toLocaleTimeString()}</span>
            <button className="refresh-btn" onClick={refresh}>↻</button>
          </div>
        </div>
      </header>
      <main className="dashboard">
        <PlaceOrderForm onOrderPlaced={refresh} />
        <MetricsCard metrics={metrics} />
        <MakelineQueue queue={queue} onComplete={async (id) => { await api.completeOrder(id); refresh() }} />
      </main>
    </div>
  )
}

export default App
