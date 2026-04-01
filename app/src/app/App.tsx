import { RouterProvider } from 'react-router';
import { router } from './routes';
import { ConfigProvider } from './contexts/ConfigContext';
import { Toaster } from './components/ui/sonner';
import { ErrorBoundary } from './components/ErrorBoundary';

export default function App() {
  return (
    <ErrorBoundary>
      <ConfigProvider>
        <RouterProvider router={router} />
        <Toaster position="top-center" />
      </ConfigProvider>
    </ErrorBoundary>
  );
}