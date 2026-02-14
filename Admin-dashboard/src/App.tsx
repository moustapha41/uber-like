import { useState } from 'react';
import { AdminAuthProvider, useAdminAuth } from './contexts/AdminAuthContext';
import AdminLogin from './pages/AdminLogin';
import DashboardLayout from './components/DashboardLayout';
import Overview from './pages/Overview';
import Drivers from './pages/Drivers';
import Rides from './pages/Rides';
import Deliveries from './pages/Deliveries';
import Pricing from './pages/Pricing';
import Audit from './pages/Audit';

function AppContent() {
  const { isAuthenticated } = useAdminAuth();
  const [currentPage, setCurrentPage] = useState('overview');

  if (!isAuthenticated) {
    return <AdminLogin />;
  }

  const renderPage = () => {
    switch (currentPage) {
      case 'overview':
        return <Overview />;
      case 'drivers':
        return <Drivers />;
      case 'rides':
        return <Rides />;
      case 'deliveries':
        return <Deliveries />;
      case 'pricing':
        return <Pricing />;
      case 'audit':
        return <Audit />;
      default:
        return <Overview />;
    }
  };

  return (
    <DashboardLayout currentPage={currentPage} onNavigate={setCurrentPage}>
      {renderPage()}
    </DashboardLayout>
  );
}

function App() {
  return (
    <AdminAuthProvider>
      <AppContent />
    </AdminAuthProvider>
  );
}

export default App;
