import { useState, useEffect, useCallback } from 'react'
import { Container, Navbar, Nav, Badge, Card, Row, Col, Table, Button, Form, Tab, Tabs, Spinner, Alert } from 'react-bootstrap'
import 'bootstrap/dist/css/bootstrap.min.css'
import './App.css'

// ── Types ─────────────────────────────────────────────────────────────────────

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
  completedAt: string | null
}

interface QueueSummary {
  totalQueued: number
  totalProcessing: number
  orders: WorkOrder[]
}

interface OrderSummary {
  orderId: string
  customerName: string
  orderTotal: number
  storeId: string
  orderDate: string
  status: string
}

// ── API ───────────────────────────────────────────────────────────────────────

const emptyQueue: QueueSummary = { totalQueued: 0, totalProcessing: 0, orders: [] }

async function safeFetch<T>(url: string, fallback: T): Promise<T> {
  try {
    const r = await fetch(url)
    if (!r.ok) return fallback
    const data = await r.json()
    return data ?? fallback
  } catch { return fallback }
}

const api = {
  placeOrder: (body: unknown) =>
    fetch('/api/orders', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }),
  getMetrics: (): Promise<OrderMetrics[]> => safeFetch('/api/accounting/metrics', []),
  getQueue: (): Promise<QueueSummary> => safeFetch('/api/makeline/orders', emptyQueue),
  getOrderHistory: (): Promise<OrderSummary[]> => safeFetch('/api/accounting/orders?limit=100', []),
  completeOrder: (orderId: string) =>
    fetch(`/api/makeline/orders/${orderId}/complete`, { method: 'PUT' }),
}

// ── Sub-components ────────────────────────────────────────────────────────────

function KpiCards({ metrics, queue }: { metrics: OrderMetrics[], queue: QueueSummary }) {
  const totals = (metrics ?? []).reduce(
    (acc, m) => ({ orders: acc.orders + (m.totalOrders ?? 0), revenue: acc.revenue + (m.totalRevenue ?? 0) }),
    { orders: 0, revenue: 0 }
  )
  const kpis = [
    { label: 'Total Orders', value: totals.orders.toLocaleString(), icon: '📦', color: 'primary' },
    { label: 'Total Revenue', value: `$${totals.revenue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`, icon: '💰', color: 'success' },
    { label: 'Queued', value: String(queue?.totalQueued ?? 0), icon: '⏳', color: 'warning' },
    { label: 'Processing', value: String(queue?.totalProcessing ?? 0), icon: '⚙️', color: 'info' },
  ]
  return (
    <Row className="g-3 mb-4">
      {kpis.map(k => (
        <Col key={k.label} xs={6} lg={3}>
          <Card className={`border-0 shadow-sm h-100 kpi-card kpi-${k.color}`}>
            <Card.Body className="d-flex align-items-center gap-3 py-3">
              <div className="kpi-icon">{k.icon}</div>
              <div>
                <div className="kpi-value">{k.value}</div>
                <div className="kpi-label text-muted">{k.label}</div>
              </div>
            </Card.Body>
          </Card>
        </Col>
      ))}
    </Row>
  )
}

function PlaceOrderTab({ onOrderPlaced }: { onOrderPlaced: () => void }) {
  const [form, setForm] = useState({
    customerName: '', loyaltyId: '', productName: 'Red Dog Burger', quantity: 1, unitPrice: 9.99,
  })
  const [status, setStatus] = useState<'idle' | 'sending' | 'success' | 'error'>('idle')
  const [errorMsg, setErrorMsg] = useState('')

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
      setTimeout(() => { setStatus('idle'); onOrderPlaced() }, 2000)
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Unknown error')
      setStatus('error')
      setTimeout(() => setStatus('idle'), 4000)
    }
  }

  return (
    <Row className="justify-content-center">
      <Col md={8} lg={6}>
        <Card className="border-0 shadow-sm">
          <Card.Header className="bg-primary text-white">
            <h5 className="mb-0">🛒 New Order</h5>
          </Card.Header>
          <Card.Body className="p-4">
            {status === 'success' && <Alert variant="success">✅ Order placed successfully! Routing to kitchen…</Alert>}
            {status === 'error' && <Alert variant="danger">❌ {errorMsg || 'Failed to place order'}</Alert>}
            <Form onSubmit={submit}>
              <Row className="g-3">
                <Col md={8}>
                  <Form.Group>
                    <Form.Label>Customer Name <span className="text-danger">*</span></Form.Label>
                    <Form.Control required placeholder="Jane Smith" value={form.customerName}
                      onChange={e => setForm(f => ({ ...f, customerName: e.target.value }))} />
                  </Form.Group>
                </Col>
                <Col md={4}>
                  <Form.Group>
                    <Form.Label>Loyalty ID <span className="text-muted">(optional)</span></Form.Label>
                    <Form.Control placeholder="LOY-12345" value={form.loyaltyId}
                      onChange={e => setForm(f => ({ ...f, loyaltyId: e.target.value }))} />
                  </Form.Group>
                </Col>
                <Col xs={12}>
                  <Form.Group>
                    <Form.Label>Product <span className="text-danger">*</span></Form.Label>
                    <Form.Control required value={form.productName}
                      onChange={e => setForm(f => ({ ...f, productName: e.target.value }))} />
                  </Form.Group>
                </Col>
                <Col xs={6}>
                  <Form.Group>
                    <Form.Label>Quantity</Form.Label>
                    <Form.Control type="number" min={1} value={form.quantity}
                      onChange={e => setForm(f => ({ ...f, quantity: +e.target.value }))} />
                  </Form.Group>
                </Col>
                <Col xs={6}>
                  <Form.Group>
                    <Form.Label>Unit Price ($)</Form.Label>
                    <Form.Control type="number" step="0.01" min="0.01" value={form.unitPrice}
                      onChange={e => setForm(f => ({ ...f, unitPrice: +e.target.value }))} />
                  </Form.Group>
                </Col>
                <Col xs={12}>
                  <div className="d-flex justify-content-between align-items-center bg-light rounded p-3">
                    <span className="text-muted">Order Total</span>
                    <strong className="fs-5">${(form.quantity * form.unitPrice).toFixed(2)}</strong>
                  </div>
                </Col>
                <Col xs={12}>
                  <Button type="submit" variant="primary" size="lg" className="w-100" disabled={status === 'sending'}>
                    {status === 'sending' ? <><Spinner size="sm" className="me-2" />Placing Order…</> : '🚀 Place Order'}
                  </Button>
                </Col>
              </Row>
            </Form>
          </Card.Body>
        </Card>
      </Col>
    </Row>
  )
}

function KitchenQueueTab({ queue, onComplete, onRefresh }: { queue: QueueSummary, onComplete: (id: string) => void, onRefresh: () => void }) {
  const active = queue.orders?.filter(o => o.status !== 'completed') ?? []
  return (
    <>
      <div className="d-flex align-items-center gap-2 mb-3">
        <Badge bg="success" pill className="fs-6 px-3">{queue.totalQueued} Queued</Badge>
        <Badge bg="warning" text="dark" pill className="fs-6 px-3">{queue.totalProcessing} Processing</Badge>
        <Button variant="outline-secondary" size="sm" className="ms-auto" onClick={onRefresh}>↻ Refresh</Button>
      </div>
      {active.length === 0
        ? <div className="text-center text-muted py-5"><div className="display-4">🎉</div><p className="mt-2">Kitchen queue is clear!</p></div>
        : (
          <Row className="g-3">
            {active.map(order => (
              <Col key={order.orderId} md={6} xl={4}>
                <Card className={`h-100 border-0 shadow-sm queue-card queue-${order.status}`}>
                  <Card.Body>
                    <div className="d-flex justify-content-between align-items-start mb-2">
                      <div>
                        <strong>{order.customerName}</strong>
                        <div className="text-muted small font-monospace">#{order.orderId.slice(0, 8)}</div>
                      </div>
                      <Badge bg={order.status === 'queued' ? 'success' : 'warning'} text={order.status === 'processing' ? 'dark' : undefined}>
                        {order.status === 'processing' ? <><Spinner size="sm" className="me-1" />{order.status}</> : order.status}
                      </Badge>
                    </div>
                    <div className="d-flex justify-content-between align-items-center">
                      <span className="fs-5 fw-bold text-primary">${(order.orderTotal ?? 0).toFixed(2)}</span>
                      {order.status === 'queued' && (
                        <Button variant="outline-success" size="sm" onClick={() => onComplete(order.orderId)}>✅ Complete</Button>
                      )}
                    </div>
                    <div className="text-muted small mt-2">
                      Queued {new Date(order.queuedAt).toLocaleTimeString()}
                    </div>
                  </Card.Body>
                </Card>
              </Col>
            ))}
          </Row>
        )
      }
    </>
  )
}

function OrderHistoryTab({ orders, loading }: { orders: OrderSummary[], loading: boolean }) {
  if (loading) return <div className="text-center py-5"><Spinner /><p className="mt-2 text-muted">Loading order history…</p></div>
  if (orders.length === 0) return <div className="text-center text-muted py-5"><div className="display-4">📋</div><p className="mt-2">No orders yet</p></div>
  return (
    <Card className="border-0 shadow-sm">
      <Card.Body className="p-0">
        <Table hover responsive className="mb-0 order-history-table">
          <thead className="table-dark">
            <tr>
              <th>Order ID</th>
              <th>Customer</th>
              <th>Store</th>
              <th>Total</th>
              <th>Date</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {orders.map(o => (
              <tr key={o.orderId}>
                <td><code className="text-primary">{o.orderId.slice(0, 8)}…</code></td>
                <td>{o.customerName}</td>
                <td><Badge bg="secondary">{o.storeId}</Badge></td>
                <td><strong>${(o.orderTotal ?? 0).toFixed(2)}</strong></td>
                <td className="text-muted small">{o.orderDate ? new Date(o.orderDate).toLocaleString() : '—'}</td>
                <td>
                  <Badge bg={o.status === 'pending' ? 'warning' : 'success'} text={o.status === 'pending' ? 'dark' : undefined}>
                    {o.status}
                  </Badge>
                </td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Card.Body>
    </Card>
  )
}

function MetricsTab({ metrics }: { metrics: OrderMetrics[] }) {
  if (metrics.length === 0) return <div className="text-center text-muted py-5"><Spinner /><p className="mt-2">Loading metrics…</p></div>
  return (
    <Row className="g-3">
      {metrics.map(m => (
        <Col key={m.storeId} md={6} xl={4}>
          <Card className="border-0 shadow-sm h-100">
            <Card.Header className="bg-dark text-white d-flex align-items-center gap-2">
              <span>🏪</span> <strong>{m.storeId}</strong>
            </Card.Header>
            <Card.Body>
              <Row className="text-center g-2">
                <Col xs={4}>
                  <div className="fs-3 fw-bold text-primary">{m.totalOrders ?? 0}</div>
                  <div className="text-muted small">Orders</div>
                </Col>
                <Col xs={4}>
                  <div className="fs-3 fw-bold text-success">${(m.totalRevenue ?? 0).toFixed(0)}</div>
                  <div className="text-muted small">Revenue</div>
                </Col>
                <Col xs={4}>
                  <div className="fs-3 fw-bold text-info">${(m.avgOrderValue ?? 0).toFixed(2)}</div>
                  <div className="text-muted small">Avg Order</div>
                </Col>
              </Row>
            </Card.Body>
          </Card>
        </Col>
      ))}
    </Row>
  )
}

// ── App ───────────────────────────────────────────────────────────────────────

function App() {
  const [metrics, setMetrics] = useState<OrderMetrics[]>([])
  const [queue, setQueue] = useState<QueueSummary>({ totalQueued: 0, totalProcessing: 0, orders: [] })
  const [orderHistory, setOrderHistory] = useState<OrderSummary[]>([])
  const [historyLoading, setHistoryLoading] = useState(false)
  const [activeTab, setActiveTab] = useState('place-order')
  const [lastRefresh, setLastRefresh] = useState(new Date())

  const refreshQueueAndMetrics = useCallback(async () => {
    try {
      const [m, q] = await Promise.all([api.getMetrics(), api.getQueue()])
      setMetrics(m); setQueue(q); setLastRefresh(new Date())
    } catch (err) { console.error('Refresh failed:', err) }
  }, [])

  const loadOrderHistory = useCallback(async () => {
    setHistoryLoading(true)
    try {
      const h = await api.getOrderHistory()
      setOrderHistory(h)
    } catch (err) { console.error('History load failed:', err) }
    finally { setHistoryLoading(false) }
  }, [])

  useEffect(() => {
    refreshQueueAndMetrics()
    const t = setInterval(refreshQueueAndMetrics, 10_000)
    return () => clearInterval(t)
  }, [refreshQueueAndMetrics])

  // Load history when that tab is selected
  useEffect(() => {
    if (activeTab === 'history') loadOrderHistory()
  }, [activeTab, loadOrderHistory])

  return (
    <>
      <Navbar bg="dark" variant="dark" expand="lg" className="shadow-sm app-navbar">
        <Container fluid="xl">
          <Navbar.Brand className="d-flex align-items-center gap-2">
            <span className="fs-4">🐕</span>
            <span className="fw-bold">Red Dog</span>
            <span className="text-muted fw-normal d-none d-sm-inline">Order Management</span>
          </Navbar.Brand>
          <Nav className="ms-auto d-flex align-items-center gap-2 flex-row">
            <Badge bg="primary" className="tech-pill">Dapr</Badge>
            <Badge bg="info" text="dark" className="tech-pill">ACA</Badge>
            <Badge bg="warning" text="dark" className="tech-pill">KEDA</Badge>
            <span className="text-muted small ms-2 d-none d-md-inline">
              Updated {lastRefresh.toLocaleTimeString()}
            </span>
            <Button variant="outline-light" size="sm" onClick={refreshQueueAndMetrics} className="ms-1">↻</Button>
          </Nav>
        </Container>
      </Navbar>

      <Container fluid="xl" className="py-4">
        <KpiCards metrics={metrics} queue={queue} />

        <Tabs activeKey={activeTab} onSelect={k => setActiveTab(k ?? 'place-order')} className="mb-4 nav-tabs-custom" fill>

          <Tab eventKey="place-order" title={<><span className="me-1">🛒</span> Place Order</>}>
            <div className="pt-2">
              <PlaceOrderTab onOrderPlaced={refreshQueueAndMetrics} />
            </div>
          </Tab>

          <Tab eventKey="kitchen" title={
            <><span className="me-1">👨‍🍳</span> Kitchen Queue
              {queue.totalQueued + queue.totalProcessing > 0 &&
                <Badge bg="danger" pill className="ms-2">{queue.totalQueued + queue.totalProcessing}</Badge>}
            </>
          }>
            <div className="pt-2">
              <KitchenQueueTab queue={queue} onRefresh={refreshQueueAndMetrics}
                onComplete={async (id) => { await api.completeOrder(id); refreshQueueAndMetrics() }} />
            </div>
          </Tab>

          <Tab eventKey="history" title={<><span className="me-1">📋</span> Order History</>}>
            <div className="pt-2">
              <div className="d-flex justify-content-end mb-3">
                <Button variant="outline-secondary" size="sm" onClick={loadOrderHistory}>↻ Refresh</Button>
              </div>
              <OrderHistoryTab orders={orderHistory} loading={historyLoading} />
            </div>
          </Tab>

          <Tab eventKey="metrics" title={<><span className="me-1">📊</span> Store Metrics</>}>
            <div className="pt-2">
              <MetricsTab metrics={metrics} />
            </div>
          </Tab>

        </Tabs>
      </Container>

      <footer className="text-center text-muted small py-3 border-top mt-auto">
        Red Dog Demo · Dapr on Azure Container Apps · Polyglot Microservices
      </footer>
    </>
  )
}

export default App
