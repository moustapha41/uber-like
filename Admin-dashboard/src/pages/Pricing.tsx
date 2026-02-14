import { useEffect, useState } from 'react';
import { Save, Bike, Package, DollarSign } from 'lucide-react';
import { api } from '../services/api';

interface RidePricing {
  baseFare: number;
  pricePerKm: number;
  pricePerMinute: number;
}

interface DeliveryPricing {
  baseFare: number;
  pricePerKm: number;
  pricePerKg: number;
}

export default function Pricing() {
  const [ridePricing, setRidePricing] = useState<RidePricing>({
    baseFare: 500,
    pricePerKm: 200,
    pricePerMinute: 50,
  });

  const [deliveryPricing, setDeliveryPricing] = useState<DeliveryPricing>({
    baseFare: 800,
    pricePerKm: 250,
    pricePerKg: 100,
  });

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState<'rides' | 'deliveries' | null>(null);
  const [saveSuccess, setSaveSuccess] = useState<'rides' | 'deliveries' | null>(null);

  useEffect(() => {
    loadPricing();
  }, []);

  const loadPricing = async () => {
    try {
      const [ridesData, deliveriesData] = await Promise.all([
        api.getRidePricing(),
        api.getDeliveryPricing(),
      ]);
      if (ridesData) setRidePricing(ridesData);
      if (deliveriesData) setDeliveryPricing(deliveriesData);
    } catch (error) {
      console.error('Failed to load pricing:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSaveRidePricing = async () => {
    setSaving('rides');
    setSaveSuccess(null);
    try {
      await api.updateRidePricing(ridePricing);
      setSaveSuccess('rides');
      setTimeout(() => setSaveSuccess(null), 3000);
    } catch (error) {
      console.error('Failed to save ride pricing:', error);
    } finally {
      setSaving(null);
    }
  };

  const handleSaveDeliveryPricing = async () => {
    setSaving('deliveries');
    setSaveSuccess(null);
    try {
      await api.updateDeliveryPricing(deliveryPricing);
      setSaveSuccess('deliveries');
      setTimeout(() => setSaveSuccess(null), 3000);
    } catch (error) {
      console.error('Failed to save delivery pricing:', error);
    } finally {
      setSaving(null);
    }
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
      <div className="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div className="flex items-center gap-3 mb-6">
          <div className="bg-blue-100 p-3 rounded-lg">
            <Bike className="w-6 h-6 text-blue-600" />
          </div>
          <div>
            <h3 className="text-xl font-bold text-slate-900">Tarification des Courses</h3>
            <p className="text-sm text-slate-600">Configurez les prix pour les courses de moto</p>
          </div>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              Frais de Base (FCFA)
            </label>
            <div className="relative">
              <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
              <input
                type="number"
                value={ridePricing.baseFare}
                onChange={(e) => setRidePricing({ ...ridePricing, baseFare: Number(e.target.value) })}
                className="w-full pl-10 pr-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
                placeholder="500"
              />
            </div>
            <p className="text-xs text-slate-500 mt-1">Montant fixe de départ pour chaque course</p>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              Prix par Kilomètre (FCFA)
            </label>
            <div className="relative">
              <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
              <input
                type="number"
                value={ridePricing.pricePerKm}
                onChange={(e) => setRidePricing({ ...ridePricing, pricePerKm: Number(e.target.value) })}
                className="w-full pl-10 pr-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
                placeholder="200"
              />
            </div>
            <p className="text-xs text-slate-500 mt-1">Coût par kilomètre parcouru</p>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              Prix par Minute (FCFA)
            </label>
            <div className="relative">
              <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
              <input
                type="number"
                value={ridePricing.pricePerMinute}
                onChange={(e) => setRidePricing({ ...ridePricing, pricePerMinute: Number(e.target.value) })}
                className="w-full pl-10 pr-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
                placeholder="50"
              />
            </div>
            <p className="text-xs text-slate-500 mt-1">Coût par minute de trajet</p>
          </div>

          <div className="pt-4 border-t border-slate-200">
            <div className="bg-blue-50 rounded-lg p-4 mb-4">
              <h4 className="text-sm font-semibold text-blue-900 mb-2">Exemple de calcul</h4>
              <p className="text-sm text-blue-800">
                Course de 10 km, 15 minutes:{' '}
                <span className="font-bold">
                  {ridePricing.baseFare + (ridePricing.pricePerKm * 10) + (ridePricing.pricePerMinute * 15)} FCFA
                </span>
              </p>
              <p className="text-xs text-blue-700 mt-1">
                = {ridePricing.baseFare} (base) + {ridePricing.pricePerKm * 10} (km) + {ridePricing.pricePerMinute * 15} (min)
              </p>
            </div>

            {saveSuccess === 'rides' && (
              <div className="bg-green-50 border border-green-200 rounded-lg p-3 mb-4">
                <p className="text-sm text-green-800 font-medium">
                  Tarification des courses mise à jour avec succès
                </p>
              </div>
            )}

            <button
              onClick={handleSaveRidePricing}
              disabled={saving === 'rides'}
              className="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white font-semibold py-3 rounded-lg transition flex items-center justify-center gap-2"
            >
              <Save className="w-5 h-5" />
              {saving === 'rides' ? 'Enregistrement...' : 'Enregistrer les Modifications'}
            </button>
          </div>
        </div>
      </div>

      <div className="bg-white rounded-xl shadow-sm border border-slate-200 p-6">
        <div className="flex items-center gap-3 mb-6">
          <div className="bg-green-100 p-3 rounded-lg">
            <Package className="w-6 h-6 text-green-600" />
          </div>
          <div>
            <h3 className="text-xl font-bold text-slate-900">Tarification des Livraisons</h3>
            <p className="text-sm text-slate-600">Configurez les prix pour les livraisons</p>
          </div>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              Frais de Base (FCFA)
            </label>
            <div className="relative">
              <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
              <input
                type="number"
                value={deliveryPricing.baseFare}
                onChange={(e) => setDeliveryPricing({ ...deliveryPricing, baseFare: Number(e.target.value) })}
                className="w-full pl-10 pr-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none"
                placeholder="800"
              />
            </div>
            <p className="text-xs text-slate-500 mt-1">Montant fixe de départ pour chaque livraison</p>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              Prix par Kilomètre (FCFA)
            </label>
            <div className="relative">
              <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
              <input
                type="number"
                value={deliveryPricing.pricePerKm}
                onChange={(e) => setDeliveryPricing({ ...deliveryPricing, pricePerKm: Number(e.target.value) })}
                className="w-full pl-10 pr-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none"
                placeholder="250"
              />
            </div>
            <p className="text-xs text-slate-500 mt-1">Coût par kilomètre de distance</p>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-2">
              Prix par Kilogramme (FCFA)
            </label>
            <div className="relative">
              <DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
              <input
                type="number"
                value={deliveryPricing.pricePerKg}
                onChange={(e) => setDeliveryPricing({ ...deliveryPricing, pricePerKg: Number(e.target.value) })}
                className="w-full pl-10 pr-4 py-3 rounded-lg border border-slate-300 focus:ring-2 focus:ring-green-500 focus:border-transparent outline-none"
                placeholder="100"
              />
            </div>
            <p className="text-xs text-slate-500 mt-1">Coût par kilogramme de poids</p>
          </div>

          <div className="pt-4 border-t border-slate-200">
            <div className="bg-green-50 rounded-lg p-4 mb-4">
              <h4 className="text-sm font-semibold text-green-900 mb-2">Exemple de calcul</h4>
              <p className="text-sm text-green-800">
                Livraison de 5 kg sur 8 km:{' '}
                <span className="font-bold">
                  {deliveryPricing.baseFare + (deliveryPricing.pricePerKm * 8) + (deliveryPricing.pricePerKg * 5)} FCFA
                </span>
              </p>
              <p className="text-xs text-green-700 mt-1">
                = {deliveryPricing.baseFare} (base) + {deliveryPricing.pricePerKm * 8} (km) + {deliveryPricing.pricePerKg * 5} (kg)
              </p>
            </div>

            {saveSuccess === 'deliveries' && (
              <div className="bg-green-50 border border-green-200 rounded-lg p-3 mb-4">
                <p className="text-sm text-green-800 font-medium">
                  Tarification des livraisons mise à jour avec succès
                </p>
              </div>
            )}

            <button
              onClick={handleSaveDeliveryPricing}
              disabled={saving === 'deliveries'}
              className="w-full bg-green-600 hover:bg-green-700 disabled:bg-green-400 text-white font-semibold py-3 rounded-lg transition flex items-center justify-center gap-2"
            >
              <Save className="w-5 h-5" />
              {saving === 'deliveries' ? 'Enregistrement...' : 'Enregistrer les Modifications'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
