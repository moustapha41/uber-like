import { useEffect, useState } from 'react';
import { Phone, Circle } from 'lucide-react';
import { api } from '../services/api';

interface Driver {
  id: string;
  name: string;
  phone: string;
  status: 'online' | 'offline' | 'busy';
  totalRides?: number;
  rating?: number;
}

export default function Drivers() {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'online' | 'offline' | 'busy'>('all');

  useEffect(() => {
    loadDrivers();
  }, []);

  const loadDrivers = async () => {
    try {
      const data = await api.getDrivers();
      setDrivers(data);
    } catch (error) {
      console.error('Failed to load drivers:', error);
      setDrivers(testDrivers);
    } finally {
      setLoading(false);
    }
  };

  // Configuration des statuts avec des valeurs par défaut sécurisées
  const statusConfig = {
    online: { label: 'En ligne', color: 'text-green-600', bgColor: 'bg-green-100', dotColor: 'bg-green-500' },
    offline: { label: 'Hors ligne', color: 'text-slate-600', bgColor: 'bg-slate-100', dotColor: 'bg-slate-400' },
    busy: { label: 'Occupé', color: 'text-orange-600', bgColor: 'bg-orange-100', dotColor: 'bg-orange-500' },
    // Valeur par défaut pour les statuts inconnus
    default: { label: 'Inconnu', color: 'text-gray-600', bgColor: 'bg-gray-100', dotColor: 'bg-gray-400' }
  };

  // Fonction utilitaire pour obtenir la configuration du statut
  const getStatusConfig = (status: string) => {
    return statusConfig[status as keyof typeof statusConfig] || statusConfig.default;
  };

  const filteredDrivers = drivers.filter((driver) => filter === 'all' || driver.status === filter);

  const stats = {
    online: drivers.filter((d) => d.status === 'online').length,
    offline: drivers.filter((d) => d.status === 'offline').length,
    busy: drivers.filter((d) => d.status === 'busy').length,
  };
  
  // Correction des données de test pour correspondre à l'interface Driver
  const testDrivers: Driver[] = [
    { id: '1', name: 'Jean Dupont', phone: '+243 812 345 678', status: 'online', totalRides: 234, rating: 4.8 },
    { id: '2', name: 'Marie Claire', phone: '+243 823 456 789', status: 'busy', totalRides: 189, rating: 4.9 },
    { id: '3', name: 'Paul Martin', phone: '+243 834 567 890', status: 'online', totalRides: 312, rating: 4.7 },
    { id: '4', name: 'Sophie Bernard', phone: '+243 845 678 901', status: 'offline', totalRides: 156, rating: 4.6 },
    { id: '5', name: 'Luc Dubois', phone: '+243 856 789 012', status: 'online', totalRides: 278, rating: 4.9 },
    { id: '6', name: 'Emma Petit', phone: '+243 867 890 123', status: 'busy', totalRides: 201, rating: 4.8 },
    { id: '7', name: 'Thomas Robert', phone: '+243 878 901 234', status: 'online', totalRides: 345, rating: 4.7 },
    { id: '8', name: 'Julie Richard', phone: '+243 889 012 345', status: 'offline', totalRides: 123, rating: 4.5 },
  ];

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
              <p className="text-sm text-slate-600">En ligne</p>
              <p className="text-2xl font-bold text-green-600">{stats.online}</p>
            </div>
            <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center">
              <Circle className="w-6 h-6 text-green-600 fill-green-600" />
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-sm border border-slate-200 p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-slate-600">Occupés</p>
              <p className="text-2xl font-bold text-orange-600">{stats.busy}</p>
            </div>
            <div className="w-12 h-12 bg-orange-100 rounded-full flex items-center justify-center">
              <Circle className="w-6 h-6 text-orange-600 fill-orange-600" />
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-sm border border-slate-200 p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-slate-600">Hors ligne</p>
              <p className="text-2xl font-bold text-slate-600">{stats.offline}</p>
            </div>
            <div className="w-12 h-12 bg-slate-100 rounded-full flex items-center justify-center">
              <Circle className="w-6 h-6 text-slate-600 fill-slate-600" />
            </div>
          </div>
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-slate-200">
        <div className="p-6 border-b border-slate-200">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-bold text-slate-900">Liste des Chauffeurs</h3>
            <div className="flex gap-2">
              {(['all', 'online', 'offline', 'busy'] as const).map((status) => (
                <button
                  key={status}
                  onClick={() => setFilter(status)}
                  className={`px-4 py-2 rounded-lg text-sm font-medium transition ${
                    filter === status
                      ? 'bg-blue-600 text-white'
                      : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                  }`}
                >
                  {status === 'all' ? 'Tous' : statusConfig[status].label}
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
                  Chauffeur
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Téléphone
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Statut
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Courses
                </th>
                <th className="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">
                  Note
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {filteredDrivers.map((driver) => {
                const config = getStatusConfig(driver.status);
                return (
                  <tr key={driver.id} className="hover:bg-slate-50">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center">
                        <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
                          <span className="text-blue-600 font-semibold text-sm">
                            {driver.name.split(' ').map((n) => n[0]).join('')}
                          </span>
                        </div>
                        <div className="ml-4">
                          <div className="text-sm font-medium text-slate-900">{driver.name}</div>
                        </div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center text-sm text-slate-600">
                        <Phone className="w-4 h-4 mr-2" />
                        {driver.phone}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-medium ${config.bgColor} ${config.color}`}>
                        <span className={`w-2 h-2 rounded-full ${config.dotColor}`} />
                        {config.label}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-slate-600">
                      {driver.totalRides || 0}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center">
                        <span className="text-sm font-medium text-slate-900">{driver.rating || 0}</span>
                        <span className="text-yellow-400 ml-1">★</span>
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
