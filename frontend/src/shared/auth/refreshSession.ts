import type { AuthenticationResponse } from "../../domain/contracts";
import { ApiClient } from "../api/client";

const REFRESH_LOCK_NAME = "bioma:auth:refresh";

// This is intentionally module-scoped: it deduplicates React remounts in the
// current tab. The Web Lock below extends the same guarantee to every tab that
// is open on the Bioma web origin, without persisting either token in storage.
let restorePromise: Promise<AuthenticationResponse> | null = null;

function requestRefresh(): Promise<AuthenticationResponse> {
  return new ApiClient(() => null).post<AuthenticationResponse>("/v1/auth/refresh");
}

async function requestRefreshExclusively(): Promise<AuthenticationResponse> {
  if (typeof navigator === "undefined" || !navigator.locks) {
    return requestRefresh();
  }

  return navigator.locks.request(
    REFRESH_LOCK_NAME,
    { mode: "exclusive" },
    async () => requestRefresh(),
  );
}

/**
 * Restores the in-memory access token after a reload.
 *
 * Refresh tokens rotate on each use. `navigator.locks` serializes that one
 * rotation across browser tabs so a second tab cannot accidentally present an
 * already-consumed cookie. Browsers without Web Locks keep the safe per-tab
 * module promise used for React remounts.
 */
export function restoreSession(): Promise<AuthenticationResponse> {
  if (!restorePromise) {
    restorePromise = requestRefreshExclusively().catch((error: unknown) => {
      restorePromise = null;
      throw error;
    });
  }

  return restorePromise;
}
