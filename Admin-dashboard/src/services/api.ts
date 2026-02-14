/**
 * Client API Admin - Branchement sur le backend BikeRide Pro
 * Base URL: VITE_API_URL ou proxy /api/v1
 */

const API_BASE = import.meta.env.VITE_API_URL || '/api/v1';

function getToken(): string | null {
  return localStorage.getItem('admin_token');
}

function onUnauthorized(): void {
  localStorage.removeItem('admin_token');
  window.location.reload();
}

async function request<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<{ success: boolean; message?: string; data?: T }> {
  const url = endpoint.startsWith('http') ? endpoint : `${API_BASE}${endpoint}`;
  const token = getToken();
  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    ...(token && { Authorization: `Bearer ${token}` }),
    ...options.headers,
  };
  const res = await fetch(url, { ...options, headers });
  if (res.status === 401) {
    onUnauthorized();
    throw new Error('Session expirée');
  }
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(json.message || `Erreur ${res.status}`);
  }
  return json as { success: boolean; message?: string; data?: T };
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

// ——— Auth ———
export const api = {
  async login(email: string, password: string): Promise<{ token: string; user: { email: string; role?: string } }> {
    const res = await request<{ user: { id: number; email: string; role: string }; token: string; refreshToken: string }>(
      '/auth/login',
      { method: 'POST', body: JSON.stringify({ email, password }) }
    );
    if (!res.success || !res.data?.token) {
      throw new ApiError(401, (res as { message?: string }).message || 'Email ou mot de passe incorrect');
    }
    const { token, user } = res.data;
    localStorage.setItem('admin_token', token);
    return { token, user: { email: user.email, role: user.role } };
  },

  // ——— Dashboard ———
  async getDashboardStats(): Promise<{
    totalRides: number;
    activeRides: number;
    onlineDrivers: number;
    totalRevenue: number;
    trends?: { rides: number; revenue: number };
  }> {
    const res = await request<{
      users: { total: number; clients: number; drivers: number; admins: number };
      rides: { total: number; revenue: number };
      deliveries: { total: number; revenue: number };
      pending_drivers_verification: number;
      recent_rides: Array<{ id: number; ride_code: string; status: string; fare_final: number | null; created_at: string }>;
    }>('/admin');
    if (!res.success || !res.data) throw new Error('Impossible de charger les statistiques');
    const d = res.data;
    const totalRevenue = (d.rides?.revenue ?? 0) + (d.deliveries?.revenue ?? 0);
    return {
      totalRides: d.rides?.total ?? 0,
      activeRides: 0,
      onlineDrivers: d.pending_drivers_verification ?? 0,
      totalRevenue,
      trends: undefined,
    };
  },

  // ——— Drivers ———
  async getDrivers(): Promise<
    Array<{ id: string; name: string; phone: string; status: 'online' | 'offline' | 'busy'; totalRides?: number; rating?: number }>
  > {
    const res = await request<
      Array<{
        id: number;
        email: string;
        phone: string | null;
        first_name: string | null;
        last_name: string | null;
        status: string;
        is_online: boolean;
        is_available: boolean;
        total_rides: number;
        average_rating: number | null;
      }>
    >('/admin/drivers');
    if (!res.success) throw new Error('Impossible de charger les chauffeurs');
    const list = Array.isArray(res.data) ? res.data : [];
    return list.map((d) => ({
      id: String(d.id),
      name: [d.first_name, d.last_name].filter(Boolean).join(' ') || d.email || '—',
      phone: d.phone || '—',
      status: d.is_online ? (d.is_available ? 'online' : 'busy') : 'offline',
      totalRides: d.total_rides ?? 0,
      rating: d.average_rating ?? undefined,
    }));
  },

  // ——— Rides (admin all) ———
  async getRides(params: { status?: string; limit?: number; offset?: number } = {}): Promise<
    Array<{
      id: string;
      status: 'assigned' | 'in_progress' | 'completed';
      departure: string;
      destination: string;
      distance: number;
      price: number;
      time: string;
      driverName: string;
      customerName: string;
    }>
  > {
    const q = new URLSearchParams();
    if (params.status) q.set('status', params.status);
    if (params.limit != null) q.set('limit', String(params.limit));
    if (params.offset != null) q.set('offset', String(params.offset));
    const res = await request<
      Array<{
        id: number;
        ride_code: string;
        status: string;
        pickup_address: string | null;
        dropoff_address: string | null;
        estimated_distance_km: number | null;
        fare_final: number | null;
        created_at: string;
        client_id: number;
        driver_id: number | null;
      }>
    >(`/rides/admin/all?${q.toString()}`);
    if (!res.success) throw new Error('Impossible de charger les courses');
    const list = Array.isArray(res.data) ? res.data : [];
    const statusMap: Record<string, 'assigned' | 'in_progress' | 'completed'> = {
      REQUESTED: 'assigned',
      DRIVER_ASSIGNED: 'assigned',
      DRIVER_ARRIVED: 'in_progress',
      IN_PROGRESS: 'in_progress',
      COMPLETED: 'completed',
      PAID: 'completed',
      CLOSED: 'completed',
      CANCELLED_BY_CLIENT: 'completed',
      CANCELLED_BY_DRIVER: 'completed',
      CANCELLED_BY_SYSTEM: 'completed',
    };
    return list.map((r) => ({
      id: String(r.id),
      status: statusMap[r.status] || 'in_progress',
      departure: r.pickup_address || '—',
      destination: r.dropoff_address || '—',
      distance: Number(r.estimated_distance_km) || 0,
      price: Number(r.fare_final) || 0,
      time: r.created_at ? new Date(r.created_at).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : '—',
      driverName: r.driver_id ? `Chauffeur #${r.driver_id}` : '—',
      customerName: r.client_id ? `Client #${r.client_id}` : '—',
    }));
  },

  // ——— Deliveries (admin all) ———
  async getDeliveries(params: { status?: string; limit?: number; offset?: number } = {}): Promise<
    Array<{
      id: string;
      status: 'pending' | 'assigned' | 'picked_up' | 'delivered';
      driverName: string | null;
      departure: string;
      destination: string;
      time: string;
      customerName: string;
      itemDescription: string;
    }>
  > {
    const q = new URLSearchParams();
    if (params.status) q.set('status', params.status);
    if (params.limit != null) q.set('limit', String(params.limit));
    if (params.offset != null) q.set('offset', String(params.offset));
    const res = await request<
      Array<{
        id: number;
        delivery_code: string;
        status: string;
        pickup_address: string | null;
        dropoff_address: string | null;
        created_at: string;
        client_id: number;
        driver_id: number | null;
        package_description?: string | null;
      }>
    >(`/deliveries/admin/all?${q.toString()}`);
    if (!res.success) throw new Error('Impossible de charger les livraisons');
    const list = Array.isArray(res.data) ? res.data : [];
    const statusMap: Record<string, 'pending' | 'assigned' | 'picked_up' | 'delivered'> = {
      REQUESTED: 'pending',
      ASSIGNED: 'assigned',
      PICKED_UP: 'picked_up',
      IN_TRANSIT: 'picked_up',
      COMPLETED: 'delivered',
      CANCELLED_BY_CLIENT: 'pending',
      CANCELLED_BY_DRIVER: 'pending',
    };
    return list.map((d) => ({
      id: String(d.id),
      status: statusMap[d.status] || 'pending',
      driverName: d.driver_id ? `Chauffeur #${d.driver_id}` : null,
      departure: d.pickup_address || '—',
      destination: d.dropoff_address || '—',
      time: d.created_at ? new Date(d.created_at).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : '—',
      customerName: `Client #${d.client_id}`,
      itemDescription: d.package_description || '—',
    }));
  },

  // ——— Pricing ———
  async getRidePricing(): Promise<{ id?: number; baseFare: number; pricePerKm: number; pricePerMinute: number }> {
    const res = await request<Array<{ id: number; service_type: string; base_fare: number; cost_per_km: number; cost_per_minute: number }>>(
      '/admin/pricing'
    );
    if (!res.success || !Array.isArray(res.data)) throw new Error('Impossible de charger les tarifs');
    const ride = res.data.find((c) => c.service_type === 'ride');
    if (!ride) return { baseFare: 500, pricePerKm: 300, pricePerMinute: 50 };
    return {
      id: ride.id,
      baseFare: Number(ride.base_fare) || 500,
      pricePerKm: Number(ride.cost_per_km) || 300,
      pricePerMinute: Number(ride.cost_per_minute) || 50,
    };
  },

  async getDeliveryPricing(): Promise<{ id?: number; baseFare: number; pricePerKm: number; pricePerKg: number }> {
    const res = await request<Array<{ id: number; service_type: string; base_fare: number; cost_per_km: number; cost_per_minute: number }>>(
      '/admin/pricing'
    );
    if (!res.success || !Array.isArray(res.data)) throw new Error('Impossible de charger les tarifs');
    const delivery = res.data.find((c) => c.service_type === 'delivery');
    if (!delivery) return { baseFare: 600, pricePerKm: 350, pricePerKg: 60 };
    return {
      id: delivery.id,
      baseFare: Number(delivery.base_fare) || 600,
      pricePerKm: Number(delivery.cost_per_km) || 350,
      pricePerKg: Number(delivery.cost_per_minute) || 60,
    };
  },

  async updateRidePricing(data: { baseFare?: number; pricePerKm?: number; pricePerMinute?: number }): Promise<void> {
    const current = await this.getRidePricing();
    const id = (current as { id?: number }).id;
    if (!id) throw new Error('Config course introuvable');
    const res = await request(`/admin/pricing/${id}`, {
      method: 'PUT',
      body: JSON.stringify({
        base_fare: data.baseFare,
        cost_per_km: data.pricePerKm,
        cost_per_minute: data.pricePerMinute,
      }),
    });
    if (!res.success) throw new Error((res as { message?: string }).message || 'Erreur mise à jour');
  },

  async updateDeliveryPricing(data: { baseFare?: number; pricePerKm?: number; pricePerKg?: number }): Promise<void> {
    const current = await this.getDeliveryPricing();
    const id = (current as { id?: number }).id;
    if (!id) throw new Error('Config livraison introuvable');
    const res = await request(`/admin/pricing/${id}`, {
      method: 'PUT',
      body: JSON.stringify({
        base_fare: data.baseFare,
        cost_per_km: data.pricePerKm,
        cost_per_minute: data.pricePerKg,
      }),
    });
    if (!res.success) throw new Error((res as { message?: string }).message || 'Erreur mise à jour');
  },

  // ——— Audit ———
  async getAuditLogs(params: {
    entity_type?: string;
    user_id?: string;
    action?: string;
    date_from?: string;
    date_to?: string;
    limit?: number;
    offset?: number;
  } = {}): Promise<{ logs: Array<{ id: string; timestamp: string; user_id: string; action: string; entity_type: string; entity_id: string; details?: string }>; total: number }> {
    const q = new URLSearchParams();
    if (params.entity_type) q.set('entity_type', params.entity_type);
    if (params.user_id) q.set('user_id', params.user_id);
    if (params.action) q.set('action', params.action);
    if (params.date_from) q.set('date_from', params.date_from);
    if (params.date_to) q.set('date_to', params.date_to);
    if (params.limit != null) q.set('limit', String(params.limit));
    if (params.offset != null) q.set('offset', String(params.offset));
    const res = await request<{ logs: Array<{ id: number; user_id: number; action: string; entity_type: string; entity_id: number; details: unknown; created_at: string }>; total: number }>(
      `/admin/audit?${q.toString()}`
    );
    if (!res.success || !res.data) throw new Error('Impossible de charger les logs');
    const d = res.data;
    const logs = (d.logs || []).map((l) => ({
      id: String(l.id),
      timestamp: l.created_at ? new Date(l.created_at).toLocaleString('fr-FR') : '—',
      user_id: String(l.user_id),
      action: l.action,
      entity_type: l.entity_type,
      entity_id: String(l.entity_id),
      details: typeof l.details === 'object' ? JSON.stringify(l.details) : String(l.details ?? ''),
    }));
    return { logs, total: d.total ?? 0 };
  },
};
