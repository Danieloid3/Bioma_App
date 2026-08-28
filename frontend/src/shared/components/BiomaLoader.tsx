export function BiomaLoader({ label = "Cargando…" }: { label?: string }) {
  return (
    <div className="bioma-loader" role="status" aria-live="polite">
      <img src="/favicon.png" alt="" aria-hidden="true" />
      <span>{label}</span>
      <span className="bioma-loader-dots" aria-hidden="true"><i /><i /><i /></span>
    </div>
  );
}
