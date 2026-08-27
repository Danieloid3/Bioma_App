import { LogOut, ShieldCheck } from "lucide-react";
import { useTranslation } from "react-i18next";

import type { Researcher } from "../../domain/contracts";
import { AnimalAvatar } from "../../shared/components/AnimalAvatar";

export function ProfilePanel({ researcher, onLogout }: { researcher: Researcher; onLogout: () => void }) {
  const { t } = useTranslation();
  return <section className="profile-card" aria-label={t("profile.title") }><AnimalAvatar avatarKey={researcher.animal_avatar_key} seed={researcher.researcher_id} /><div><p className="eyebrow">{t("profile.signedIn")}</p><h2>{researcher.full_name}</h2><p>{researcher.role_title}</p><span className="level-pill"><ShieldCheck aria-hidden="true" />{t("profile.level", { level: researcher.accreditation_level })}</span></div><button className="button text" onClick={onLogout} type="button"><LogOut aria-hidden="true" />{t("profile.logout")}</button></section>;
}
