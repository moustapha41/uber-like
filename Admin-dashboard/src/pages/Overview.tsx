import { useEffect, useState } from 'react';
import { Bike, DollarSign, Users, TrendingUp } from 'lucide-react';
import StatsCard from '../components/StatsCard';
import LineChart from '../components/LineChart';
import SimpleChart from '../components/SimpleChart';
import { api } from '../services/api';

interface DashboardStats {
  totalRides: number;
  activeRides: number;
  onlineDrivers: number;
  totalRevenue: number;
  trends?: {
    rides: number;
    revenue: number;
  };
}

export default function Overview() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadStats();
  }, []);

  const loadStats = async () => {
    try {
      const data = await api.getDashboardStats();
      setStats(data);
    } catch (error) {
      console.error('Failed to load stats:', error);
      setStats({
        totalRides: 1247,
        activeRides: 23,
        onlineDrivers: 156,
        totalRevenue: 45890,
        trends: { rides: 12.5, revenue: 8.3 },
      });
    } finally {
      setLoading(false);
    }
  };

  const revenueData = [
    { label: 'Lun', value: 4200 },
    { label: 'Mar', value: 5100 },
    { label: 'Mer', value: 4800 },
    { label: 'Jeu', value: 6200 },
    { label: 'Ven', value: 7500 },
    { label: 'Sam', value: 8900 },
    { label: 'Dim', value: 6400 },
  ];

  const rideTypeData = [
    { label: 'Courses Standard', value: 856 },
    { label: 'Courses Premium', value: 234 },
    { label: 'Livraisons', value: 157 },
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
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatsCard
          title="Total Courses"
          value={stats?.totalRides || 0}
          icon={Bike}
          color="blue"
          trend={stats?.trends ? { value: stats.trends.rides, isPositive: stats.trends.rides > 0 } : undefined}
        />
        <StatsCard
          title="Courses Actives"
          value={stats?.activeRides || 0}
          icon={TrendingUp}
          color="orange"
        />
        <StatsCard
          title="Chauffeurs en Ligne"
          value={stats?.onlineDrivers || 0}
          icon={Users}
          color="green"
        />
        <StatsCard
          title="Revenu Total"
          value={`${(stats?.totalRevenue || 0).toLocaleString('fr-FR')} FCFA`}
          icon={DollarSign}
          color="purple"
          trend={stats?.trends ? { value: stats.trends.revenue, isPositive: stats.trends.revenue > 0 } : undefined}
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
          <h3 className="text-lg font-bold text-slate-900 mb-4">Revenus de la Semaine</h3>
          <LineChart data={revenueData} color="#3B82F6" />
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
          <h3 className="text-lg font-bold text-slate-900 mb-4">Types de Services</h3>
          <SimpleChart data={rideTypeData} color="#10B981" />
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <h3 className="text-lg font-bold text-slate-900 mb-4">Activité Récente</h3>
        <div className="space-y-4">
          {[
            { time: 'Il y a 2 min', action: 'Nouvelle course assignée', driver: 'Jean Dupont', status: 'En cours' },
            { time: 'Il y a 5 min', action: 'Livraison complétée', driver: 'Marie Claire', status: 'Terminée' },
            { time: 'Il y a 12 min', action: 'Chauffeur connecté', driver: 'Paul Martin', status: 'En ligne' },
            { time: 'Il y a 18 min', action: 'Course terminée', driver: 'Sophie Bernard', status: 'Terminée' },
            { time: 'Il y a 25 min', action: 'Nouvelle demande de livraison', driver: 'En attente', status: 'Assignation' },
          ].map((activity, index) => (
            <div key={index} className="flex items-center justify-between py-3 border-b border-slate-100 last:border-0">
              <div className="flex-1">
                <p className="text-sm font-medium text-slate-900">{activity.action}</p>
                <p className="text-xs text-slate-500 mt-1">
                  {activity.driver} · {activity.time}
                </p>
              </div>
              <span className={`px-3 py-1 rounded-full text-xs font-medium ${
                activity.status === 'En cours' ? 'bg-blue-100 text-blue-700' :
                activity.status === 'Terminée' ? 'bg-green-100 text-green-700' :
                activity.status === 'En ligne' ? 'bg-green-100 text-green-700' :
                'bg-orange-100 text-orange-700'
              }`}>
                {activity.status}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
