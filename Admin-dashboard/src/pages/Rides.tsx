import { useEffect, useState } from 'react';
import { MapPin, Clock, DollarSign } from 'lucide-react';
import { api } from '../services/api';

interface Ride {
  id: string;
  status: 'assigned' | 'in_progress' | 'completed';
  departure: string;
  destination: string;
  distance: number;
  price: number;
  time: string;
  driverName: string;
  customerName: string;
}

export default function Rides() {
  const [rides, setRides] = useState<Ride[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'assigned' | 'in_progress' | 'completed'>('all');

  useEffect(() => {
    loadRides();
  }, []);

  const loadRides = async () => {
    try {
      const data = await api.getRides();
      setRides(data);
    } catch (error) {
      console.error('Failed to load rides:', error);
      setRides([
        {
          id: '1',
          status: 'in_progress',
          departure: 'Gombe, Kinshasa',
          destination: 'Ngaliema, Kinshasa',
          distance: 8.5,
          price: 3500,
          time: '14:30',
          driverName: 'Jean Dupont',
          customerName: 'Alice Martin',
        },
        {
          id: '2',
          status: 'assigned',
          departure: 'Limete, Kinshasa',
          destination: 'Kintambo, Kinshasa',
          distance: 5.2,
          price: 2200,
          time: '14:45',
          driverName: 'Marie Claire',
          customerName: 'Bob Durant',
        },
        {
          id: '3',
          status: 'completed',
          departure: 'Masina, Kinshasa',
          destination: 'Lemba, Kinshasa',
          distance: 12.3,
          price: 4800,
          time: '13:20',
          driverName: 'Paul Martin',
          customerName: 'Claire Dubois',
        },
        {
          id: '4',
          status: 'in_progress',
          departure: 'Bandalungwa, Kinshasa',
          destination: 'Kalamu, Kinshasa',
          distance: 3.7,
          price: 1800,
          time: '14:50',
          driverName: 'Sophie Bernard',
          customerName: 'David Petit',
        },
        {
          id: '5',
          status: 'completed',
          departure: 'Barumbu, Kinshasa',
          destination: 'Kinshasa, Centre-ville',
          distance: 6.8,
          price: 2900,
          time: '12:15',
          driverName: 'Luc Dubois',
          customerName: 'Emma Robert',
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  const filteredRides = rides.filter((ride) => filter === 'all' || ride.status === filter);

  const statusConfig = {
    assigned: { label: 'Assignée', color: 'text-blue-700', bgColor: 'bg-blue-100' },
    in_progress: { label: 'En progression', color: 'text-orange-700', bgColor: 'bg-orange-100' },
    completed: { label: 'Complétée', color: 'text-green-700', bgColor: 'bg-green-100' },
    default: { label: 'Inconnu', color: 'text-gray-700', bgColor: 'bg-gray-100' },
  };

  const getStatusConfig = (status: string) => {
    return statusConfig[status as keyof typeof statusConfig] || statusConfig.default;
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
      <div className="bg-white rounded-xl shadow-sm border border-slate-200">
        <div className="p-6 border-b border-slate-200">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-bold text-slate-900">Courses Récentes</h3>
            <div className="flex gap-2">
              {(['all', 'assigned', 'in_progress', 'completed'] as const).map((status) => (
                <button
                  key={status}
                  onClick={() => setFilter(status)}
                  className={`px-4 py-2 rounded-lg text-sm font-medium transition ${
                    filter === status
                      ? 'bg-blue-600 text-white'
                      : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                  }`}
                >
                  {status === 'all' ? 'Toutes' : statusConfig[status].label}
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
                  Départ
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Destination
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Distance
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Prix
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Heure
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Chauffeur
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {filteredRides.map((ride) => {
                const config = getStatusConfig(ride.status);
                return (
                  <tr key={ride.id} className="hover:bg-slate-50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-3 py-1 rounded-full text-xs font-medium ${config.bgColor} ${config.color}`}>
                        {config.label}
                      </span>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex items-start gap-2">
                        <MapPin className="w-4 h-4 text-green-600 mt-0.5 flex-shrink-0" />
                        <span className="text-sm text-slate-900">{ride.departure}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex items-start gap-2">
                        <MapPin className="w-4 h-4 text-red-600 mt-0.5 flex-shrink-0" />
                        <span className="text-sm text-slate-900">{ride.destination}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                      {ride.distance} km
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-1 text-sm font-medium text-slate-900">
                        <DollarSign className="w-4 h-4" />
                        {ride.price.toLocaleString('fr-FR')} FCFA
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2 text-sm text-slate-600">
                        <Clock className="w-4 h-4" />
                        {ride.time}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-slate-900">
                      {ride.driverName}
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
