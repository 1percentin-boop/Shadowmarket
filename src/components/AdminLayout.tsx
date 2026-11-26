import { motion } from 'framer-motion';
import { Shield, LogOut } from 'lucide-react';
import { ToastContainer } from './ToastContainer';
import { useMarket } from '../context/MarketContext';
import { useState } from 'react';

export function AdminLayout({ children }: { children: React.ReactNode }) {
  const { supabaseSignOut } = useMarket();
  const [signingOut, setSigningOut] = useState(false);

  const handleSignOut = async () => {
    setSigningOut(true);
    await supabaseSignOut();
    setSigningOut(false);
    window.location.href = '/';
  };

  return (
    <div className="min-h-screen bg-base text-gray-100">
      <header className="sticky top-0 z-40 flex w-full items-center justify-between gap-3 border-b border-[#1F1F24] bg-[#060608] p-4 md:p-6">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-amber-400/30 bg-amber-400/10">
            <Shield size={18} className="text-amber-400" />
          </div>
          <div className="hidden sm:block">
            <p className="text-sm font-semibold tracking-tight text-white">Super Admin Portal</p>
            <p className="text-[10px] uppercase tracking-[0.2em] text-amber-400/70">Platform Control</p>
          </div>
        </div>

        <button
          onClick={handleSignOut}
          disabled={signingOut}
          className="inline-flex items-center gap-1.5 rounded-xl border border-[#1F1F24] bg-[#111114] px-3 py-2 text-xs font-medium text-platinum transition-all hover:border-red-500/40 hover:text-red-400 disabled:opacity-50"
        >
          <LogOut size={14} />
          <span className="hidden sm:inline">Sign Out</span>
        </button>
      </header>

      <motion.main
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.35, ease: 'easeOut' }}
        className="mx-auto max-w-7xl px-4 pt-4 pb-20 lg:px-8"
      >
        {children}
      </motion.main>
      <ToastContainer />
    </div>
  );
}
