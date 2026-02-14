import { useEffect, useState } from 'react';
import { MapPin, Clock, Package } from 'lucide-react';
import { api } from '../services/api';

interface Delivery {
  id: string;
  status: 'pending' | 'assigned' | 'picked_up' | 'delivered';
  driverName: string | null;
  departure: string;
  destination: string;
  time: string;
  customerName: string;
  itemDescription: string;
}

export default function Deliveries() {
  const [deliveries, setDeliveries] = useState<Delivery[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'pending' | 'in_progress' | 'delivered'>('all');

  useEffect(() => {
    loadDeliveries();
  }, []);

  const loadDeliveries = async () => {
    try {
      const data = await api.getDeliveries();
      setDeliveries(data);
    } catch (error) {
      console.error('Failed to load deliveries:', error);
      setDeliveries([
        {
          id: '1',
          status: 'picked_up',
          driverName: 'Jean Dupont',
          departure: 'Restaurant Le Gourmet, Gombe',
          destination: 'Av. Kasai 123, Kinshasa',
          time: '15:20',
          customerName: 'Alice Martin',
          itemDescription: 'Nourriture (2 plats)',
        },
        {
          id: '2',
          status: 'pending',
          driverName: null,
          departure: 'Pharmacie Centrale, Limete',
          destination: 'Rue Kasa-Vubu 45, Kinshasa',
          time: '15:35',
          customerName: 'Bob Durant',
          itemDescription: 'Médicaments',
        },
        {
          id: '3',
          status: 'delivered',
          driverName: 'Marie Claire',
          departure: 'Boutique Mode, Kintambo',
          destination: 'Av. Lumumba 78, Kinshasa',
          time: '14:10',
          customerName: 'Claire Dubois',
          itemDescription: 'Vêtements (colis)',
        },
        {
          id: '4',
          status: 'assigned',
          driverName: 'Paul Martin',
          departure: 'Supermarché Express, Masina',
          destination: 'Bd. Triomphal 234, Kinshasa',
          time: '15:40',
          customerName: 'David Petit',
          itemDescription: 'Courses (5kg)',
        },
        {
          id: '5',
          status: 'delivered',
          driverName: 'Sophie Bernard',
          departure: 'Librairie Moderne, Bandalungwa',
          destination: 'Rue de la Paix 12, Kinshasa',
          time: '13:45',
          customerName: 'Emma Robert',
          itemDescription: 'Livres (3 unités)',
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const getFilteredDeliveries = () => {
    if (filter === 'all') return deliveries;
    if (filter === 'in_progress') return deliveries.filter((d) => d.status === 'assigned' || d.status === 'picked_up');
    return deliveries.filter((d) => d.status === filter);
  };

  const filteredDeliveries = getFilteredDeliveries();

  const statusConfig = {
    pending: { label: 'En attente', color: 'text-slate-700', bgColor: 'bg-slate-100' },
    assigned: { label: 'Assignée', color: 'text-blue-700', bgColor: 'bg-blue-100' },
    picked_up: { label: 'Récupérée', color: 'text-orange-700', bgColor: 'bg-orange-100' },
    delivered: { label: 'Livrée', color: 'text-green-700', bgColor: 'bg-green-100' },
    default: { label: 'Inconnu', color: 'text-gray-700', bgColor: 'bg-gray-100' },
  };

  const getStatusConfig = (status: string) => {
    return statusConfig[status as keyof typeof statusConfig] || statusConfig.default;
  };

  const stats = {
    pending: deliveries.filter((d) => d.status === 'pending').length,
    inProgress: deliveries.filter((d) => d.status === 'assigned' || d.status === 'picked_up').length,
    delivered: deliveries.filter((d) => d.status === 'delivered').length,
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-white rounded-lg shadow-sm border border-slate-200 p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-slate-600">En attente</p>
              <p className="text-2xl font-bold text-slate-900">{stats.pending}</p>
            </div>
            <div className="w-12 h-12 bg-slate-100 rounded-full flex items-center justify-center">
              <Package className="w-6 h-6 text-slate-600" />
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-sm border border-slate-200 p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-slate-600">En cours</p>
              <p className="text-2xl font-bold text-orange-600">{stats.inProgress}</p>
            </div>
            <div className="w-12 h-12 bg-orange-100 rounded-full flex items-center justify-center">
              <Package className="w-6 h-6 text-orange-600" />
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-sm border border-slate-200 p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-slate-600">Livrées</p>
              <p className="text-2xl font-bold text-green-600">{stats.delivered}</p>
            </div>
            <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center">
              <Package className="w-6 h-6 text-green-600" />
            </div>
          </div>
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-slate-200">
        <div className="p-6 border-b border-slate-200">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-bold text-slate-900">Demandes de Livraison</h3>
            <div className="flex gap-2">
              {(['all', 'pending', 'in_progress', 'delivered'] as const).map((status) => (
                <button
                  key={status}
                  onClick={() => setFilter(status)}
                  className={`px-4 py-2 rounded-lg text-sm font-medium transition ${
                    filter === status
                      ? 'bg-blue-600 text-white'
                      : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                  }`}
                >
                  {status === 'all' ? 'Toutes' : status === 'in_progress' ? 'En cours' : getStatusConfig(status).label}
                </button>
              ))}
            </div>
          </div>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-slate-50 border-b border-slate-200">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Statut
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Chauffeur
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Point de Départ
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Destination
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Description
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Heure
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {filteredDeliveries.map((delivery) => {
                const config = getStatusConfig(delivery.status);
                return (
                  <tr key={delivery.id} className="hover:bg-slate-50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-3 py-1 rounded-full text-xs font-medium ${config.bgColor} ${config.color}`}>
                        {config.label}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-slate-900">
                      {delivery.driverName || (
                        <span className="text-slate-400 italic">Non assigné</span>
                      )}
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex items-start gap-2">
                        <MapPin className="w-4 h-4 text-green-600 mt-0.5 flex-shrink-0" />
                        <span className="text-sm text-slate-900">{delivery.departure}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex items-start gap-2">
                        <MapPin className="w-4 h-4 text-red-600 mt-0.5 flex-shrink-0" />
                        <span className="text-sm text-slate-900">{delivery.destination}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-2">
                        <Package className="w-4 h-4 text-slate-400" />
                        <span className="text-sm text-slate-600">{delivery.itemDescription}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2 text-sm text-slate-600">
                        <Clock className="w-4 h-4" />
                        {delivery.time}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
