import { LogOut, ShieldCheck } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";

import type { Researcher } from "../../domain/contracts";
import type { ApiClient } from "../../shared/api/client";
import { AnimalAvatar } from "../../shared/components/AnimalAvatar";

export function ProfilePanel({ api, researcher, onLogout, onNavigate }: { api: ApiClient; researcher: Researcher; onLogout: () => void; onNavigate: (view: "admin") => void }) {
  const { t } = useTranslation();
  const adminAccess = useQuery({ queryKey: ["admin-access"], queryFn: () => api.get<unknown[]>("/v1/admin/system-prompts"), retry: false });
  return <div className="profile-settings"><section className="profile-card" aria-label={t("profile.title") }><AnimalAvatar avatarKey={researcher.animal_avatar_key} seed={researcher.researcher_id} /><div><p className="eyebrow">{t("profile.signedIn")}</p><h2>{researcher.full_name}</h2><p>{researcher.role_title}</p><span className="level-pill"><ShieldCheck aria-hidden="true" />{t("profile.level", { level: researcher.accreditation_level })}</span></div><button className="button text" onClick={onLogout} type="button"><LogOut aria-hidden="true" />{t("profile.logout")}</button></section>{adminAccess.isSuccess && <section className="profile-admin-card"><div><p className="eyebrow">{t("nav.admin")}</p><h2>{t("adminPrompts.title")}</h2><p>{t("profile.adminDescription")}</p></div><button className="button secondary" type="button" onClick={() => onNavigate("admin")}>{t("profile.openAdmin")}</button></section>}</div>;
}
